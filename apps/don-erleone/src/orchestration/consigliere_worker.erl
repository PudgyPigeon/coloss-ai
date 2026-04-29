-module(consigliere_worker).
-behaviour(gen_server).
-behaviour(poolboy_worker).
-include("records.hrl").

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2]).

-ifdef(TEST).
-compile(export_all).
-endif.

%% Poolboy passes arguments as a list; we unwrap it here.
start_link([Config]) ->
    gen_server:start_link(?MODULE, Config, []).

init(Config) ->
    {ok, Config}.

%% The caller From is the cowboy handler's {Pid, Tag}, NOT the gen_server caller.
%% We manually reply to the cowboy process and return {reply, ok} to release
%% the pool worker back to poolboy.
handle_call({consult, SessionId, Prompt, CowboyFrom}, _PoolFrom, Config) ->
    %% do_consult now handles sending the messages to Cowboy directly
    case do_consult(SessionId, Prompt, Config, CowboyFrom) of
        ok -> 
            {reply, ok, Config};
        {error, Reason} -> 
            {CowboyPid, CowboyTag} = CowboyFrom,
            CowboyPid ! {CowboyTag, {error, Reason}},
            {reply, {error, Reason}, Config}
    end.

%% --- Internal: Parse Ollama response and decide routing ---

do_consult(SessionId, Prompt, Config, CowboyFrom) ->
    try
        %% Filter out legacy integer tokens to ensure compatibility with new chat history
        PrevContext0 = mission_store:get_latest_context(SessionId),
        PrevContext = [M || M <- PrevContext0, is_map(M)],
        case call_ollama(Prompt, PrevContext, Config) of
            {ok, OllamaData} ->
                process_and_route(SessionId, OllamaData, Prompt, PrevContext, CowboyFrom);
            {error, Reason} ->
                {error, Reason}
        end
    catch
        Class:Error:Stack ->
            logger:error("Worker crash: ~p:~p~n~p", [Class, Error, Stack]),
            {error, {worker_crash, Error}}
    end.

process_and_route(SessionId, OllamaData, Prompt, PrevContext, CowboyFrom) ->
    {MissionData, RawContent} = extract_mission_data(OllamaData),
    IsDelegated = maps:get(<<"delegate_required">>, MissionData),
    
    UserMsg = #{<<"role">> => <<"user">>, <<"content">> => to_bin(Prompt)},
    AsstMsg = #{<<"role">> => <<"assistant">>, <<"content">> => RawContent},
    NewContext = PrevContext ++ [UserMsg, AsstMsg],
    
    MissionDataWithCtx = MissionData#{<<"context">> => NewContext},
    route_mission(SessionId, IsDelegated, MissionDataWithCtx, Prompt, CowboyFrom).

to_bin(Data) when is_binary(Data) -> Data;
to_bin(Data) when is_list(Data) -> list_to_binary(Data);
to_bin(Data) -> iolist_to_binary(io_lib:format("~p", [Data])).

route_mission(SessionId, true, MissionData, Prompt, CowboyFrom) ->
    handle_delegated_mission(SessionId, MissionData, Prompt, CowboyFrom);
route_mission(SessionId, false, MissionData, Prompt, CowboyFrom) ->
    handle_direct_answer(SessionId, MissionData, Prompt, CowboyFrom).

handle_delegated_mission(SessionId, MissionData, Prompt, CowboyFrom) ->
    #{
        <<"tool_intent">> := Intent,
        <<"context">> := NewContext,
        <<"response">> := Response,
        <<"mcp_args">> := Args
    } = MissionData,
    {ok, Id} = mission_store:post_mission(SessionId, Intent, Prompt, NewContext),

    logger:info("Worker ~p delegated mission ~p (intent=~s)", [self(), Id, Intent]),

    %% 1. Send the Consigliere's acknowledgment to the user as a CHUNK
    %% (e.g., "I am delegating this to the Kubernetes agent...")
    {CowboyPid, CowboyTag} = CowboyFrom,
    CowboyPid ! {CowboyTag, {chunk, Response, Id}},

    %% 2. Dispatch to the Underboss (who will eventually send the 'done' message)
    MissionSpec = build_mission_spec(Id, SessionId, Intent, Args, Prompt, CowboyFrom),
    underboss:dispatch_mission(MissionSpec),
    
    ok. %% We return ok, the worker is done.

handle_direct_answer(SessionId, MissionData, Prompt, CowboyFrom) ->
    #{<<"context">> := NewContext, <<"response">> := Response} = MissionData,
    {ok, Id} = mission_store:post_mission(SessionId, <<"direct_answer">>, Prompt, NewContext),
    
    %% The Consigliere has the final answer, so we send the DONE message.
    {CowboyPid, CowboyTag} = CowboyFrom,
    CowboyPid ! {CowboyTag, {done, Response, Id}},
    
    ok. %% Return ok, worker is done.
build_mission_spec(Id, SessionId, Intent, Args, Prompt, CowboyFrom) ->
    #{
        id => Id,
        session_id => SessionId,
        intent => Intent,
        args => Args,
        prompt => Prompt,
        cowboy_from => CowboyFrom
    }.

extract_mission_data(FinalText) when is_binary(FinalText) ->
    %% LLMs sometimes wrap JSON in markdown blocks. We provide both 
    %% the raw text and a stripped version to our JSON finder to be safe.
    StrippedText = string:replace(string:replace(FinalText, <<"```json\n">>, <<>>), <<"```">>, <<>>),
    
    RawOptions = [FinalText, StrippedText],
    ActualData = find_json_payload(RawOptions),
    
    {#{
        <<"response">> => maps:get(<<"response">>, ActualData, <<"Acknowledged.">>),
        <<"delegate_required">> => maps:get(<<"delegate_required">>, ActualData, false),
        <<"tool_intent">> => maps:get(<<"tool_intent">>, ActualData, <<"unknown">>),
        <<"mcp_args">> => maps:get(<<"mcp_args">>, ActualData, #{})
    }, FinalText}.

%% --- Internal: Extract JSON from Ollama's various response fields ---

find_json_payload([Bin | T]) when is_binary(Bin), Bin =/= <<>> ->
    try
        jsx:decode(Bin, [return_maps])
    catch
        _:_ -> find_json_payload(T)
    end;
find_json_payload([_ | T]) ->
    find_json_payload(T);
find_json_payload([]) ->
    #{}.

%% --- Internal: HTTP call to Ollama ---

call_ollama(Prompt, PrevContext, #config{
    model = M, stream = S, system_prompt = SP, ollama_url = URL, timeout = T
}) ->
    Opts = #{url => URL, model => M, timeout => T, stream => S},
    ollama_client:generate(Prompt, SP, PrevContext, Opts).

%% Standard callbacks
handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Msg, State) -> {noreply, State}.

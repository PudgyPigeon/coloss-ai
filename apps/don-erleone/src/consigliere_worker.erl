-module(consigliere_worker).
-behaviour(gen_server).
-behaviour(poolboy_worker).
-include("records.hrl").

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% Poolboy passes arguments as a list; we unwrap it here.
start_link([Config]) ->
    gen_server:start_link(?MODULE, Config, []).

init(Config) ->
    {ok, Config}.

%% The caller From is the cowboy handler's {Pid, Tag}, NOT the gen_server caller.
%% We manually reply to the cowboy process and return {reply, ok} to release
%% the pool worker back to poolboy.
handle_call({consult, SessionId, Prompt, CowboyFrom}, _PoolFrom, Config) ->
    Result = do_consult(SessionId, Prompt, Config),

    %% Reply directly to the cowboy handler process
    {CowboyPid, CowboyTag} = CowboyFrom,
    CowboyPid ! {CowboyTag, Result},

    %% Tell poolboy this worker is done (releases back to pool)
    {reply, ok, Config}.

%% --- Internal: Parse Ollama response and decide routing ---

do_consult(SessionId, Prompt, Config) ->
    try
        PrevContext = mission_store:get_latest_context(SessionId),
        case call_ollama(Prompt, PrevContext, Config) of
            {ok, OllamaData} ->
                process_and_route(SessionId, OllamaData, Prompt);
            {error, Reason} ->
                {error, Reason}
        end
    catch
        Class:Error:Stack ->
            logger:error("Worker crash: ~p:~p~n~p", [Class, Error, Stack]),
            {error, {worker_crash, Error}}
    end.

process_and_route(SessionId, OllamaData, Prompt) ->
    MissionData = extract_mission_data(OllamaData),
    IsDelegated = maps:get(<<"delegate_required">>, MissionData),
    route_mission(SessionId, IsDelegated, MissionData, Prompt).

route_mission(SessionId, true, MissionData, Prompt) ->
    handle_delegated_mission(SessionId, MissionData, Prompt);

route_mission(SessionId, false, MissionData, Prompt) ->
    handle_direct_answer(SessionId, MissionData, Prompt).

handle_delegated_mission(SessionId, MissionData, Prompt) ->
    #{ <<"tool_intent">> := Intent, <<"context">> := NewContext,
       <<"response">> := Response, <<"mcp_args">> := Args } = MissionData,
    {ok, Id} = mission_store:post_mission(SessionId, Intent, Prompt, NewContext),

    logger:info("Worker ~p delegated mission ~p (intent=~s, session=~s)",
                [self(), Id, Intent, SessionId]),

    MissionSpec = build_mission_spec(Id, SessionId, Intent, Args, Prompt),
    underboss:dispatch_mission(MissionSpec),
    {ok, Response, #{mission_id => Id}}.

handle_direct_answer(SessionId, MissionData, Prompt) ->
    #{ <<"context">> := NewContext, <<"response">> := Response } = MissionData,
    {ok, Id} = mission_store:post_mission(SessionId, <<"direct_answer">>, Prompt, NewContext),
    {ok, Response, #{mission_id => Id}}.

build_mission_spec(Id, SessionId, Intent, Args, Prompt) ->
    #{ id => Id, session_id => SessionId, intent => Intent,
       args => Args, prompt => Prompt }.

extract_mission_data(OllamaData) ->
    RawOptions = [
        maps:get(<<"response">>, OllamaData, <<>>),
        maps:get(<<"thinking">>, OllamaData, <<>>),
        maps:get(<<"content">>, OllamaData, <<>>)
    ],
    ActualData = find_json_payload(RawOptions),
    #{
        <<"response">> => maps:get(<<"response">>, ActualData, <<"Acknowledged.">>),
        <<"delegate_required">> => maps:get(<<"delegate_required">>, ActualData, false),
        <<"tool_intent">> => maps:get(<<"tool_intent">>, ActualData, <<"unknown">>),
        <<"mcp_args">> => maps:get(<<"mcp_args">>, ActualData, #{}),
        <<"context">> => maps:get(<<"context">>, OllamaData, [])
    }.

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

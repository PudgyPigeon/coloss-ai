-module(consigliere_worker).
-behaviour(gen_server).
-behaviour(poolboy_worker).
-include("records.hrl").

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% --- Lifecycle ---

start_link([Config]) ->
    gen_server:start_link(?MODULE, Config, []).

init(Config) ->
    logger:info("Consigliere Worker ~p online", [self()]),
    {ok, Config}.

%% --- Core API ---

handle_call({consult, SessionId, Prompt, CowboyFrom}, _PoolFrom, Config) ->
    case execute_consultation(SessionId, Prompt, CowboyFrom, Config) of
        ok -> {reply, ok, Config};
        {error, Reason} -> 
            notify_error(CowboyFrom, Reason),
            {reply, {error, Reason}, Config}
    end.

%% --- High-Level Flow ---

execute_consultation(SessionId, Prompt, CowboyFrom, Config) ->
    try
        Context = get_cleaned_context(SessionId),
        case call_ollama(Prompt, Context, Config) of
            {ok, OllamaData} ->
                handle_ollama_response(SessionId, Prompt, OllamaData, Context, CowboyFrom);
            {error, Reason} ->
                {error, Reason}
        end
    catch
        C:E:Stk ->
            logger:error("Worker Crash ~p:~p~n~p", [C, E, Stk]),
            {error, worker_fault}
    end.

handle_ollama_response(SessionId, Prompt, OllamaData, PrevContext, CowboyFrom) ->
    RawContent = extract_raw_content(OllamaData),
    ParsedJSON = parse_json_payload(RawContent),
    
    %% Normalize the data to ensure we have valid types for Erlang logic
    MissionMap = normalize_mission_data(ParsedJSON, RawContent),
    
    %% Build the updated conversation history
    NewContext = build_new_context(Prompt, RawContent, PrevContext),
    FullData = MissionMap#{<<"context">> => NewContext},
    
    route_by_intent(SessionId, FullData, Prompt, CowboyFrom).

%% --- Logic Chunks (Functional Style) ---

%% Normalization: Ensures we never have 'null' atoms where we expect binaries
normalize_mission_data(Data, RawFallback) ->
    #{
        <<"response">> => maps:get(<<"response bridge">>, Data, 
                            maps:get(<<"response">>, Data, RawFallback)),
        <<"delegate">> => maps:get(<<"delegate_required">>, Data, false),
        <<"intent">>   => ensure_bin(maps:get(<<"tool_intent">>, Data, <<"direct">>)),
        <<"args">>     => maps:get(<<"mcp_args">>, Data, #{})
    }.

route_by_intent(SessionId, #{<<"delegate">> := true} = Data, Prompt, CowboyFrom) ->
    dispatch_delegated(SessionId, Data, Prompt, CowboyFrom);
route_by_intent(SessionId, Data, Prompt, CowboyFrom) ->
    dispatch_direct(SessionId, Data, Prompt, CowboyFrom).

%% --- Mission Handlers ---

dispatch_delegated(SessionId, Data, Prompt, CowboyFrom) ->
    #{<<"intent">> := Intent, <<"context">> := Ctx, <<"response">> := Msg, <<"args">> := Args} = Data,
    {ok, Id} = mission_store:post_mission(SessionId, Intent, Prompt, Ctx),
    
    %% Notify UI that work is beginning
    send_to_cowboy(CowboyFrom, {chunk, Msg, Id}),
    
    %% Hand off to Underboss
    Spec = build_spec(Id, SessionId, Intent, Args, Prompt, CowboyFrom),
    underboss:dispatch_mission(Spec),
    ok.

dispatch_direct(SessionId, Data, Prompt, CowboyFrom) ->
    #{<<"context">> := Ctx, <<"response">> := Msg} = Data,
    {ok, Id} = mission_store:post_mission(SessionId, <<"direct_answer">>, Prompt, Ctx),
    
    send_to_cowboy(CowboyFrom, {done, Msg, Id}),
    ok.

%% --- Helpers ---

get_cleaned_context(SessionId) ->
    [M || M <- mission_store:get_latest_context(SessionId), is_map(M)].

extract_raw_content(#{<<"content">> := C}) -> C;
extract_raw_content(#{content := C}) -> C;
extract_raw_content(C) when is_binary(C) -> C;
extract_raw_content(_) -> <<"Error: Empty content from LLM">>.

parse_json_payload(Bin) ->
    %% Strip markdown backticks
    S1 = binary:replace(Bin, <<"```json">>, <<>>, [global]),
    S2 = binary:replace(S1, <<"```">>, <<>>, [global]),
    try
        jsx:decode(S2, [return_maps])
    catch
        _:_ -> #{} %% Return empty map on parse failure
    end.

build_new_context(Prompt, Response, Prev) ->
    Prev ++ [
        #{<<"role">> => <<"user">>, <<"content">> => to_bin(Prompt)},
        #{<<"role">> => <<"assistant">>, <<"content">> => to_bin(Response)}
    ].

send_to_cowboy({Pid, Tag}, Msg) -> Pid ! {Tag, Msg}.

notify_error({Pid, Tag}, Reason) -> Pid ! {Tag, {error, Reason}}.

ensure_bin(null) -> <<"none">>;
ensure_bin(B) when is_binary(B) -> B;
ensure_bin(Any) -> iolist_to_binary(io_lib:format("~p", [Any])).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> list_to_binary(L);
to_bin(Any) -> ensure_bin(Any).

build_spec(Id, Sid, Intent, Args, Prompt, From) ->
    #{id => Id, session_id => Sid, intent => Intent, args => Args, prompt => Prompt, cowboy_from => From}.

call_ollama(Prompt, Context, #config{model=M, stream=S, system_prompt=SP, ollama_url=URL, timeout=T}) ->
    ollama_client:generate(Prompt, SP, Context, #{url => URL, model => M, timeout => T, stream => S}).

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Msg, State) -> {noreply, State}.
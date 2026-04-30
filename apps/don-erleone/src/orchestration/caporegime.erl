-module(caporegime).
-include("records.hrl").
-behaviour(gen_server).
-behaviour(poolboy_worker).

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% ------------------------------------------------------------------------
%% Lifecycle & API
%% ------------------------------------------------------------------------

start_link([SubConfig]) -> 
    gen_server:start_link(?MODULE, SubConfig, []).

init(SubConfig) -> 
    %% SRE FIX: Open the persistent HTTP connection to the Haskell MCP once.
    URL = SubConfig#sub_config.mcp_url,
    #{host := H, port := P} = uri_string:parse(URL),
    Host = if is_binary(H) -> binary_to_list(H); true -> H end,
    
    case gun:open(Host, P, #{connect_timeout => 5000, protocols => [http]}) of
        {ok, Conn} ->
            %% Wait for the protocol to be up before marking the worker as ready
            {ok, _} = gun:await_up(Conn, 5000),
            %% Store BOTH the config and the warm connection in the state
            State = #{config => SubConfig, conn => Conn},
            {ok, State};
        {error, Reason} ->
            %% If the worker can't connect on boot, it crashes and Poolboy/Underboss restarts it.
            {stop, {mcp_connection_failed, Reason}}
    end.

handle_call({execute_mission, Spec}, _From, State) ->
    Mid = maps:get(id, Spec),
    mission_store:update_status(Mid, in_progress),
    
    Result = run_mission(Spec, State),
    
    finalize_mission(Spec, Result),
    {reply, Result, State}.

%% ------------------------------------------------------------------------
%% Mission Orchestration
%% ------------------------------------------------------------------------

run_mission(Spec, State) ->
    case discover_tools(State) of
        {ok, Tools} ->
            #{config := Conf} = State,
            Prompt = agent_brain:build_sub_prompt(
                maps:get(intent, Spec), 
                maps:get(prompt, Spec), 
                Tools
            ),
            recursive_loop(Prompt, [], Tools, State, 0);
        {error, Reason} -> 
            %% SRE GUARD: Hard stop if we can't discover tools. Do not send an empty toolbox to Ollama.
            {error, {infrastructure_down, Reason}}
    end.

discover_tools(State) ->
    case mcp_call(<<"tools/list">>, #{}, State) of
        {ok, Body} -> agent_brain:decode_tools(Body);
        Error -> Error
    end.

%% ------------------------------------------------------------------------
%% Reasoning Loop
%% ------------------------------------------------------------------------

recursive_loop(_P, _Ctx, _T, #{config := #sub_config{max_steps = Max}}, Step) when Step >= Max -> 
    {error, recursion_limit};

recursive_loop(Prompt, Context, Tools, State, Step) ->
    case call_ollama(Prompt, Context, Tools, State) of
        {ok, Msg} ->
            process_llm_response(Msg, Context, Tools, State, Step);
        Error -> 
            Error
    end.

call_ollama(Prompt, Context, Tools, #{config := Conf}) ->
    OllamaOpts = #{
        url => Conf#sub_config.ollama_url,
        model => Conf#sub_config.model,
        timeout => Conf#sub_config.timeout,
        stream => false
    },
    ollama_client:generate_with_tools(Prompt, <<>>, Context, Tools, OllamaOpts).

process_llm_response(Msg, Context, Tools, State, Step) ->
    case agent_brain:analyze_loop_step(Msg) of
        {continue, _Calls} when Step >= 2 -> 
            {ok, #{response => <<"Maximum discovery depth reached. Summarizing gathered cluster data from history.">>}};

        {continue, Calls} ->
            Results = [execute_tool(C, State) || C <- Calls],
            NextCtx = Context ++ [Msg#{<<"role">> => <<"assistant">>} | Results],
            recursive_loop(<<>>, NextCtx, Tools, State, Step + 1);

        {stop, Response} -> 
            {ok, #{response => Response}}
    end.

%% ------------------------------------------------------------------------
%% Tool Execution
%% ------------------------------------------------------------------------

execute_tool(#{<<"function">> := #{<<"name">> := N, <<"arguments">> := A}}, State) ->
    Params = #{<<"name">> => N, <<"arguments">> => A},
    case mcp_call(<<"tools/call">>, Params, State) of
        {ok, Res} -> 
            format_tool_response(N, extract_mcp_result(Res));
        {error, Reason} -> 
            format_tool_response(N, iolist_to_binary(io_lib:format("Error: ~p", [Reason])))
    end.

format_tool_response(Name, Content) ->
    %% SRE FIX: Changed <<"tool music">> to <<"tool">> to prevent LLM context poisoning.
    #{<<"role">> => <<"tool">>, <<"name">> => Name, <<"content">> => Content}.

extract_mcp_result(RawRes) ->
    try
        case jsx:decode(RawRes, [return_maps]) of
            #{<<"result">> := #{<<"content">> := List}} -> 
                parse_content_list(List, RawRes);
            #{<<"error">> := #{<<"message">> := M}} -> 
                <<"MCP Error: ", M/binary>>;
            _ -> 
                RawRes
        end
    catch _:_ -> RawRes end.

parse_content_list(List, Fallback) ->
    Texts = [T || #{<<"type">> := <<"text">>, <<"text">> := T} <- List],
    case Texts of
        [] -> Fallback;
        _ -> iolist_to_binary(lists:join(<<"\n">>, Texts))
    end.

%% ------------------------------------------------------------------------
%% HTTP Transport (Reusing the warm Gun connection)
%% ------------------------------------------------------------------------

mcp_call(Method, Params, #{config := Conf, conn := Conn}) ->
    {Headers, Payload} = agent_brain:prepare_mcp_request(Method, Params),
    #{path := Path} = uri_string:parse(Conf#sub_config.mcp_url),
    
    %% SRE FIX: No open/close here. Just push the request through the existing socket.
    Ref = gun:post(Conn, Path, Headers, Payload),
    await_gun_response(Conn, Ref, Conf#sub_config.timeout).

await_gun_response(Conn, Ref, Timeout) ->
    case gun:await(Conn, Ref, Timeout) of
        {response, nofin, 200, _} -> gun:await_body(Conn, Ref, Timeout);
        {response, _, Status, _} -> {error, {http_status, Status}};
        _ -> {error, timeout}
    end.

%% ------------------------------------------------------------------------
%% Helpers & Cleanup
%% ------------------------------------------------------------------------

finalize_mission(#{id := Mid, cowboy_from := From}, {ok, Data}) ->
    mission_store:complete_mission(Mid, Data),
    safe_notify(From, {done, maps:get(response, Data), Mid});
finalize_mission(#{id := Mid, cowboy_from := From}, {error, R}) ->
    mission_store:fail_mission(Mid, R),
    safe_notify(From, {error, R}).

safe_notify({Pid, Tag}, Msg) -> 
    case is_process_alive(Pid) of
        true -> Pid ! {Tag, Msg};
        false -> ok
    end.

terminate(_Reason, #{conn := Conn}) ->
    %% SRE FIX: Ensure we cleanly close the socket if the worker is killed
    gun:close(Conn),
    ok.

handle_cast(_, S) -> {noreply, S}.
handle_info(_, S) -> {noreply, S}.
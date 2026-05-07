-module(de_caporegime).
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
    %% Lazy Connection: don't block boot on MCP availability.
    %% This prevents Poolboy from crashing the whole app on localhost.
    {ok, #{config => SubConfig, conn => undefined}}.

handle_call({execute_mission, Spec}, _From, State) ->
    Mid = maps:get(id, Spec),
    logger:info(#{event => de_caporegime_mission_start, mission_id => Mid}),
    de_store:update_status(Mid, in_progress),
    
    case ensure_conn(State) of
        {ok, NewState} ->
            Result = run_mission(Spec, NewState),
            finalize_mission(Spec, Result),
            {reply, Result, NewState};
        {error, Reason} ->
            logger:error(#{event => mcp_connection_failed, mission_id => Mid, error => Reason}),
            Result = {error, {infrastructure_down, Reason}},
            finalize_mission(Spec, Result),
            {reply, Result, State}
    end.

%% ------------------------------------------------------------------------
%% Self-Healing Connection Manager
%% ------------------------------------------------------------------------

ensure_conn(#{conn := Conn} = State) when is_pid(Conn) ->
    case is_process_alive(Conn) of
        true -> 
            {ok, State};
        false -> 
            %% The Gun process died silently. Reconnect.
            logger:warning(#{event => de_caporegime_socket_dead, action => reconnecting}),
            reconnect(State)
    end;
ensure_conn(State) ->
    reconnect(State).

reconnect(#{config := Conf} = State) ->
    %% 1. Sanity check: Ensure we don't leave zombie Gun processes behind
    case maps:get(conn, State, undefined) of
        OldConn when is_pid(OldConn) -> gun:close(OldConn);
        _ -> ok
    end,

    %% 2. Dial the MCP
    URL = Conf#sub_config.mcp_url,
    #{host := H, port := P} = uri_string:parse(URL),
    Host = if is_binary(H) -> binary_to_list(H); true -> H end,
    
    logger:info(#{event => de_caporegime_connecting_mcp, host => Host, port => P}),
    
    %% We use a tight connect timeout so the worker doesn't hang the pool forever
    case gun:open(Host, P, #{connect_timeout => 10000, protocols => [http]}) of
        {ok, NewConn} ->
            case gun:await_up(NewConn, 10000) of
                {ok, _} ->
                    logger:info(#{event => de_caporegime_connected, host => Host}),
                    {ok, State#{conn => NewConn}};
                {error, Reason} ->
                    gun:close(NewConn),
                    {error, {await_up_failed, Reason}}
            end;
        {error, Reason} ->
            {error, {gun_open_failed, Reason}}
    end.

%% ------------------------------------------------------------------------
%% Mission Orchestration
%% ------------------------------------------------------------------------

run_mission(Spec, State) ->
    case discover_tools(State) of
        {ok, Tools} ->
            logger:debug(#{event => tools_discovered, count => length(Tools)}),
            Prompt = de_agent_brain:build_sub_prompt(
                maps:get(intent, Spec), 
                maps:get(prompt, Spec), 
                Tools
            ),
            recursive_loop(Prompt, [], Tools, State, 0);
        {error, Reason} -> 
            logger:error(#{event => tool_discovery_failed, error => Reason}),
            %% SRE GUARD: Hard stop if we can't discover tools. Do not send an empty toolbox to Ollama.
            {error, {infrastructure_down, Reason}}
    end.

discover_tools(State) ->
    case mcp_call(<<"tools/list">>, #{}, State) of
        {ok, Body} -> de_agent_brain:decode_tools(Body);
        Error -> Error
    end.

%% ------------------------------------------------------------------------
%% Reasoning Loop
%% ------------------------------------------------------------------------

recursive_loop(_P, _Ctx, _T, #{config := #sub_config{max_steps = Max}}, Step) when Step >= Max -> 
    {error, recursion_limit};

recursive_loop(Prompt, Context, Tools, State, Step) ->
    logger:debug(#{event => de_caporegime_loop_step, step => Step}),
    case call_ollama(Prompt, Context, Tools, State) of
        {ok, Msg} ->
            process_llm_response(Msg, Context, Tools, State, Step);
        Error -> 
            logger:error(#{event => de_caporegime_ollama_failed, error => Error}),
            Error
    end.

call_ollama(Prompt, Context, Tools, #{config := Conf}) ->
    OllamaOpts = #{
        url => Conf#sub_config.ollama_url,
        model => Conf#sub_config.model,
        timeout => Conf#sub_config.timeout,
        stream => false
    },
    de_ollama_client:generate_with_tools(Prompt, <<>>, Context, Tools, OllamaOpts).

process_llm_response(Msg, Context, Tools, State, Step) ->
    case de_agent_brain:analyze_loop_step(Msg) of
        %% Execute the tool calls, but don't increment the Step. 
        %% If Step is maxed out, force the LLM to summarize next round.
        {continue, Calls} ->
            Results = [execute_tool(C, State) || C <- Calls],
            NextCtx = Context ++ [Msg#{<<"role">> => <<"assistant">>} | Results],
            
            %% SRE FIX: Check max depth AFTER executing the tool, not before.
            #{config := #sub_config{max_steps = Max}} = State,
            if 
                Step >= Max -> 
                    %% Force termination instead of looping again
                    {ok, #{response => <<"I have executed the final tool call. Please check the logs." >>}};
                true ->
                    recursive_loop(<<>>, NextCtx, Tools, State, Step + 1)
            end;

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
    {Headers, Payload} = de_agent_brain:prepare_mcp_request(Method, Params),
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
    de_store:complete_mission(Mid, Data),
    safe_notify(From, {done, maps:get(response, Data), Mid});
finalize_mission(#{id := Mid, cowboy_from := From}, {error, R}) ->
    de_store:fail_mission(Mid, R),
    safe_notify(From, {error, R}).

safe_notify({Pid, Tag}, Msg) -> 
    case is_process_alive(Pid) of
        true -> Pid ! {Tag, Msg};
        false -> ok
    end.

terminate(_Reason, #{conn := Conn}) ->
    %% SRE FIX: Ensure we cleanly close the socket if the worker is killed
    case Conn of
        Pid when is_pid(Pid) -> gun:close(Pid);
        _ -> ok
    end,
    ok.

handle_cast(_, S) -> {noreply, S}.
handle_info(_, S) -> {noreply, S}.
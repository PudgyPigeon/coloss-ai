-module(caporegime).
-include("records.hrl").
-behaviour(gen_server).
-behaviour(poolboy_worker).

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% ------------------------------------------------------------------------
%% Lifecycle & Poolboy Setup
%% ------------------------------------------------------------------------

start_link([SubConfig]) -> 
    gen_server:start_link(?MODULE, SubConfig, []).

init(SubConfig) -> 
    {ok, SubConfig}.

%% ------------------------------------------------------------------------
%% Mission Control
%% ------------------------------------------------------------------------

handle_call({execute_mission, Spec}, _From, SubConfig) ->
    %% Update state in the global mission store
    Mid = maps:get(id, Spec),
    mission_store:update_status(Mid, in_progress),
    
    %% Start the heavy lifting
    Result = execute_autonomous_loop(Spec, SubConfig),
    
    %% Cleanup and Notify
    finalize_mission(Spec, Result),
    {reply, Result, SubConfig}.

execute_autonomous_loop(Spec, Conf) ->
    %% 1. Discovery Phase: See what the Haskell MCP can actually do
    case mcp_call(<<"tools/list">>, #{}, Conf) of
        {ok, Body} ->
            case agent_brain:decode_tools(Body) of
                {ok, Tools} ->
                    %% 2. Prompt Construction
                    SystemPrompt = agent_brain:build_sub_prompt(
                        maps:get(intent, Spec), 
                        maps:get(prompt, Spec), 
                        maps:get(args, Spec)
                    ),
                    %% 3. Enter Reasoning Loop
                    recursive_loop(SystemPrompt, [], Tools, Conf, 0);
                {error, R} -> 
                    {error, {discovery_decode_failed, R}}
            end;
        Error -> 
            Error
    end.

%% ------------------------------------------------------------------------
%% The Autonomous reasoning loop
%% ------------------------------------------------------------------------

%% Guard: Circuit breaker prevents the "Don" from spinning forever
recursive_loop(_P, _Ctx, _T, #sub_config{max_steps = Max}, Step) when Step >= Max -> 
    {error, recursion_limit};

recursive_loop(Prompt, Context, Tools, Conf, Step) ->
    %% SRE FIX: Convert Record to Map for the generic shared client
    OllamaOpts = #{
        url => Conf#sub_config.ollama_url,
        model => Conf#sub_config.model,
        timeout => Conf#sub_config.timeout,
        stream => false
    },

    case ollama_client:generate_with_tools(Prompt, <<>>, Context, Tools, OllamaOpts) of
        {ok, Msg} ->
            case agent_brain:analyze_loop_step(Msg) of
                {continue, Calls} ->
                    %% Execute requested tool calls from the LLM
                    Results = [run_tool(C, Conf) || C <- Calls],
                    
                    %% Update the Assistant history and Tool results
                    NextCtx = Context ++ [Msg#{<<"role">> => <<"assistant">>} | Results],
                    
                    %% Recurse with an empty prompt (LLM continues from history)
                    recursive_loop(<<>>, NextCtx, Tools, Conf, Step + 1);
                {stop, Response} -> 
                    {ok, #{response => Response}}
            end;
        {error, {http_status, 404}} -> 
            {error, model_not_found};
        Error -> 
            Error
    end.

run_tool(#{<<"function">> := #{<<"name">> := N, <<"arguments">> := A}}, Conf) ->
    case mcp_call(N, A, Conf) of
        {ok, Res} -> 
            #{<<"role">> => <<"tool">>, <<"content">> => Res};
        Error -> 
            %% Capture errors as tool content so the LLM can see the failure
            #{<<"role">> => <<"tool">>, <<"content">> => iolist_to_binary(io_lib:format("~p", [Error]))}
    end.

%% ------------------------------------------------------------------------
%% MCP Bridge (Haskell Server Transport)
%% ------------------------------------------------------------------------

mcp_call(Method, Params, Conf) ->
    {Headers, Payload} = agent_brain:prepare_mcp_request(Method, Params),
    gun_request(Conf#sub_config.mcp_url, Headers, Payload, Conf#sub_config.timeout).

gun_request(URL, Headers, Payload, Timeout) ->
    #{host := H, port := P, path := Path} = uri_string:parse(URL),
    HostList = if is_binary(H) -> binary_to_list(H); true -> H end,
    
    %% SRE FIX: Guard gun:open to avoid crashing in the 'after' block if Conn is unbound
    case gun:open(HostList, P, #{connect_timeout => 5000, protocols => [http]}) of
        {ok, Conn} ->
            try
                case gun:await_up(Conn, 5000) of
                    {ok, _} ->
                        Ref = gun:post(Conn, Path, Headers, Payload),
                        case gun:await(Conn, Ref, Timeout) of
                            {response, nofin, 200, _} -> 
                                gun:await_body(Conn, Ref, Timeout);
                            {response, _, Status, _} -> 
                                {error, {http_status, Status}};
                            _ -> 
                                {error, timeout}
                        end;
                    {error, Reason} -> 
                        {error, {connect_failed, Reason}}
                end
            after
                gun:close(Conn)
            end;
        {error, Reason} ->
            {error, {transport_failed, Reason}}
    end.

%% ------------------------------------------------------------------------
%% Output & Notifications
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

%% ------------------------------------------------------------------------
%% Unused Callbacks
%% ------------------------------------------------------------------------

handle_cast(_, S) -> {noreply, S}.
handle_info(_, S) -> {noreply, S}.
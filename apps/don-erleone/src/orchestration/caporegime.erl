-module(caporegime).
-include("records.hrl").
-behaviour(gen_server).
-behaviour(poolboy_worker).

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% ------------------------------------------------------------------------
%% Lifecycle
%% ------------------------------------------------------------------------

start_link([SubConfig]) ->
    gen_server:start_link(?MODULE, SubConfig, []).

init(SubConfig) ->
    {ok, SubConfig}.

%% ------------------------------------------------------------------------
%% API / Callbacks
%% ------------------------------------------------------------------------

handle_call({execute_mission, MissionSpec}, _From, SubConfig) ->
    #{id := MissionId, intent := Intent} = MissionSpec,
    logger:info("Caporegime ~p starting mission ~p: ~s", [self(), MissionId, Intent]),

    mission_store:update_status(MissionId, in_progress),

    %% Pipeline: Execute -> Persist Outcome -> Notify Caller
    Result = run_execution_safely(MissionSpec, SubConfig),
    persist_mission_outcome(MissionId, Result),
    dispatch_notifications(MissionSpec, Result),

    {reply, Result, SubConfig}.

%% ------------------------------------------------------------------------
%% Execution Pipeline
%% ------------------------------------------------------------------------

run_execution_safely(MissionSpec, SubConfig) ->
    try
        route_to_handler(MissionSpec, SubConfig)
    catch
        C:E:Stk ->
            logger:error("Caporegime crash: ~p:~p~n~p", [C, E, Stk]),
            {error, {mission_crash, E}}
    end.

%% Intent Routing logic
route_to_handler(#{intent := <<"k8s_deploy">>, prompt := P, args := A}, Conf) ->
    execute_ai_mission(build_sub_prompt(<<"k8s_deploy">>, P, A), Conf);

route_to_handler(#{intent := <<"check_mcp">>, prompt := P, args := A}, Conf) ->
    URL = maps:get(<<"endpoint">>, A, get_mcp_endpoint()),
    case maps:get(<<"endpoint">>, A, undefined) of
        undefined -> execute_ai_mission(build_sub_prompt(<<"check_mcp">>, P, A), Conf);
        _         -> call_mcp_raw_endpoint(URL, A, Conf)
    end;

route_to_handler(#{intent := <<"k8s_logs">>, args := A}, Conf) ->
    URL = maps:get(<<"endpoint">>, A, get_mcp_endpoint()),
    call_mcp_raw_endpoint(URL, A, Conf);

route_to_handler(#{intent := Intent, prompt := P, args := A}, Conf) ->
    execute_ai_mission(build_sub_prompt(Intent, P, A), Conf).

%% ------------------------------------------------------------------------
%% AI & Dynamic Tool Discovery
%% ------------------------------------------------------------------------

execute_ai_mission(SystemPrompt, SubConfig) ->
    %% Discovery: Query the Haskell MCP server for available tools
    case fetch_mcp_tools(SubConfig) of
        {ok, Tools} ->
            recursive_tool_loop(SystemPrompt, [], Tools, SubConfig, 0);
        {error, Reason} ->
            logger:error("Tool discovery failed: ~p", [Reason]),
            {error, {discovery_error, Reason}}
    end.

recursive_tool_loop(_P, _Ctx, _T, _Conf, 5) ->
    {error, recursion_limit_reached};
recursive_tool_loop(Prompt, Context, Tools, Conf, Depth) ->
    case call_ollama_with_tools(Prompt, Context, Tools, Conf) of
        {ok, #{<<"tool_calls">> := Calls} = Msg} ->
            NextContext = process_tool_calls(Calls, Context, Msg, Conf),
            recursive_tool_loop(<<>>, NextContext, Tools, Conf, Depth + 1);
        
        {ok, Msg} ->
            {ok, #{model => Conf#sub_config.model, response => extract_msg_content(Msg)}};
        
        Error -> Error
    end.

process_tool_calls(Calls, PrevContext, AsstMsg, Conf) ->
    CleanAsstMsg = AsstMsg#{<<"role">> => <<"assistant">>},
    ToolResults = [execute_single_tool(C, Conf) || C <- Calls],
    PrevContext ++ [CleanAsstMsg | ToolResults].

execute_single_tool(#{<<"function">> := #{<<"name">> := N, <<"arguments">> := A}}, Conf) ->
    logger:info("Caporegime calling tool: ~s", [N]),
    Result = dispatch_mcp_rpc(<<"tools/call">>, #{<<"name">> => N, <<"arguments">> => A}, Conf),
    #{<<"role">> => <<"tool">>, <<"content">> => Result}.

%% ------------------------------------------------------------------------
%% MCP Protocol Bridge (JSON-RPC)
%% ------------------------------------------------------------------------

fetch_mcp_tools(Conf) ->
    case dispatch_mcp_rpc(<<"tools/list">>, #{}, Conf) of
        {ok, #{<<"tools">> := Tools}} -> {ok, Tools};
        {error, _} = Err -> Err;
        Other -> 
            try
                #{<<"result">> := #{<<"tools">> := T}} = jsx:decode(to_bin(Other), [return_maps]),
                {ok, T}
            catch _:_ -> {error, discovery_decode_failed} end
    end.

dispatch_mcp_rpc(Method, Params, Conf) ->
    Url = get_mcp_endpoint(),
    Payload = jsx:encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"id">>      => Method,
        <<"method">>  => Method,
        <<"params">>  => Params
    }),
    case perform_http_post(Url, Payload, Conf) of
        {ok, #{response := Body}} -> 
            case Method of
                <<"tools/list">> -> decode_mcp_result(Body);
                _ -> Body
            end;
        {error, _} = Err -> Err
    end.

call_mcp_raw_endpoint(URL, Args, Conf) ->
    Params = maps:without([<<"endpoint">>], Args),
    case perform_http_post(URL, jsx:encode(Params), Conf) of
        {ok, #{response := Body}} -> 
            {ok, #{model => <<"raw_mcp">>, response => Body}};
        {error, Reason} -> 
            {error, Reason}
    end.

perform_http_post(URL, Payload, #sub_config{timeout = T}) ->
    Headers = [{"MCP-Protocol-Version", "2025-06-18"}],
    HttpOpts = [{timeout, T}, {connect_timeout, 5000}],
    case httpc:request(post, {binary_to_list(URL), Headers, "application/json", Payload}, HttpOpts, []) of
        {ok, {{_, 200, _}, _, Body}} -> {ok, #{response => iolist_to_binary(Body)}};
        {ok, {{_, Status, _}, _, _}} -> {error, {http_status, Status}};
        {error, Reason}              -> {error, Reason}
    end.

%% ------------------------------------------------------------------------
%% Prompt Construction
%% ------------------------------------------------------------------------

build_sub_prompt(<<"k8s_deploy">>, Prompt, Args) ->
    iolist_to_binary([
        <<"You are a Kubernetes deployment sub-agent.\n">>,
        <<"Generate a valid YAML manifest for the following request.\n">>,
        <<"Request: ">>, Prompt, <<"\n">>,
        <<"Arguments: ">>, jsx:encode(Args), <<"\n">>,
        <<"Respond with JSON: {\"manifest\": \"<yaml>\", \"status\": \"ready\"}">>
    ]);

build_sub_prompt(<<"check_mcp">>, Prompt, _Args) ->
    iolist_to_binary([
        <<"You are an infrastructure status sub-agent.\n">>,
        <<"Assess the following request and provide a status report.\n">>,
        <<"Request: ">>, Prompt, <<"\n">>,
        <<"Respond with JSON: {\"status\": \"...\", \"details\": \"...\"}">>
    ]);

build_sub_prompt(Intent, Prompt, Args) ->
    iolist_to_binary([
        <<"You are an autonomous Kubernetes sub-agent.\n">>,
        <<"Task intent: ">>, Intent, <<"\n">>,
        <<"Original User Request: ">>, Prompt, <<"\n">>,
        <<"Consigliere Args: ">>, jsx:encode(Args), <<"\n">>,
        <<"You have access to Kubernetes tools via MCP. ">>,
        <<"Fetch information from the cluster to fulfill the request. ">>,
        <<"Do not guess state. Summarize the final result for the user once done.">>
    ]).

%% ------------------------------------------------------------------------
%% State & Notifications
%% ------------------------------------------------------------------------

persist_mission_outcome(Id, {ok, Data})    -> mission_store:complete_mission(Id, Data);
persist_mission_outcome(Id, {error, Rsn}) -> mission_store:fail_mission(Id, Rsn).

dispatch_notifications(#{cowboy_from := {Pid, Tag}, id := Mid}, {ok, Result}) ->
    Content = extract_msg_content(Result),
    Formatted = <<"\n\n---\n**Execution Result:**\n", (to_bin(Content))/binary>>,
    Pid ! {Tag, {chunk, Formatted, Mid}},
    Pid ! {Tag, {done, <<>>, Mid}};
dispatch_notifications(#{cowboy_from := {Pid, Tag}}, {error, Reason}) ->
    Pid ! {Tag, {error, Reason}};
dispatch_notifications(_, _) -> ok.

%% ------------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------------

get_mcp_endpoint() ->
    case os:getenv("MCP_URL") of
        Value when is_list(Value) -> list_to_binary(Value);
        false ->
            application:get_env(don_erleone, mcp_url, 
                <<"http://kubernetes-mcp.kubernetes-mcp.svc.cluster.local:8080/mcp">>)
    end.

decode_mcp_result(Body) ->
    try
        #{<<"result">> := Result} = jsx:decode(Body, [return_maps]),
        Result
    catch _:_ -> {error, invalid_json_rpc} end.

extract_msg_content(#{response := R}) -> R;
extract_msg_content(#{<<"content">> := C}) -> C;
extract_msg_content(C) when is_binary(C) -> C;
extract_msg_content(_) -> <<"No content returned.">>.

to_bin(B) when is_binary(B) -> B;
to_bin(Any) -> iolist_to_binary(io_lib:format("~p", [Any])).

call_ollama_with_tools(P, Ctx, Tools, #sub_config{ollama_url = U, model = M, timeout = T}) ->
    ollama_client:generate_with_tools(P, <<>>, Ctx, Tools, #{url => U, model => M, timeout => T, stream => false}).

handle_cast(_, S) -> {noreply, S}.
handle_info(_, S) -> {noreply, S}.
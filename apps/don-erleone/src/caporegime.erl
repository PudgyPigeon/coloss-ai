-module(caporegime).
-include("records.hrl").
-behaviour(gen_server).
-behaviour(poolboy_worker).

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% Poolboy passes worker arguments as a list; we unwrap it here.
start_link([SubConfig]) ->
    gen_server:start_link(?MODULE, SubConfig, []).

init(SubConfig) ->
    {ok, SubConfig}.

%% Execute a delegated mission: call the sub-model, update mission store.
handle_call({execute_mission, MissionSpec}, _From, SubConfig) ->
    #{id := MissionId, intent := Intent} = MissionSpec,

    logger:info("Caporegime ~p executing mission ~p (intent=~s)",
                [self(), MissionId, Intent]),

    mission_store:update_status(MissionId, in_progress),

    Result = do_execute(MissionSpec, SubConfig),

    handle_result(MissionId, Result),

    {reply, Result, SubConfig}.

%% --- Task execution by intent ---

execute(<<"k8s_deploy">>, Prompt, Args, SubConfig) ->
    SubPrompt = build_sub_prompt(<<"k8s_deploy">>, Prompt, Args),
    call_sub_model(SubPrompt, SubConfig);

execute(<<"check_mcp">>, Prompt, Args, SubConfig) ->
    case maps:get(<<"endpoint">>, Args, undefined) of
        undefined ->
            %% No MCP endpoint — fall back to sub-model reasoning.
            SubPrompt = build_sub_prompt(<<"check_mcp">>, Prompt, Args),
            call_sub_model(SubPrompt, SubConfig);
        URL when is_binary(URL) ->
            call_mcp_endpoint(URL, Args, SubConfig)
    end;

execute(Intent, Prompt, Args, SubConfig) ->
    SubPrompt = build_sub_prompt(Intent, Prompt, Args),
    call_sub_model(SubPrompt, SubConfig).

%% --- Ollama sub-model call ---

call_sub_model(SubPrompt, #sub_config{
    ollama_url = URL, model = Model, timeout = Timeout
}) ->
    Opts = #{url => URL, model => Model, timeout => Timeout, stream => false},
    case ollama_client:generate(SubPrompt, <<>>, [], Opts) of
        {ok, Decoded} ->
            Response = maps:get(<<"response">>, Decoded, <<>>),
            {ok, #{model => Model, response => Response}};
        Error ->
            Error
    end.

%% --- MCP endpoint call ---

call_mcp_endpoint(URL, Args, Config) ->
    RequestBody = build_mcp_payload(Args),
    do_mcp_request(URL, RequestBody, Config).

%% --- Internal Helpers ---

do_execute(MissionSpec, SubConfig) ->
    #{id := MissionId, intent := Intent, prompt := Prompt, args := Args} = MissionSpec,
    try
        execute(Intent, Prompt, Args, SubConfig)
    catch
        Class:Error:Stack ->
            logger:error("Caporegime mission ~p crashed: ~p:~p~n~p",
                        [MissionId, Class, Error, Stack]),
            {error, {crash, Error}}
    end.

handle_result(MissionId, {ok, Data}) ->
    mission_store:complete_mission(MissionId, Data),
    logger:info("Mission ~p completed", [MissionId]);
handle_result(MissionId, {error, Reason}) ->
    mission_store:fail_mission(MissionId, Reason),
    logger:warning("Mission ~p failed: ~p", [MissionId, Reason]).

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
        <<"You are a sub-agent executing a delegated task.\n">>,
        <<"Task intent: ">>, Intent, <<"\n">>,
        <<"Request: ">>, Prompt, <<"\n">>,
        <<"Arguments: ">>, jsx:encode(Args), <<"\n">>,
        <<"Respond with JSON containing 'result' and 'status' fields.">>
    ]).

build_mcp_payload(Args) ->
    jsx:encode(maps:without([<<"endpoint">>], Args)).

do_mcp_request(URL, RequestBody, #sub_config{timeout = Timeout}) ->
    HttpOpts = [{timeout, Timeout}, {connect_timeout, 5000}],
    SafeURL = binary_to_list(URL),
    case httpc:request(post, {SafeURL, [], "application/json", RequestBody}, HttpOpts, []) of
        {ok, {{_, 200, _}, _, Body}} ->
            {ok, #{type => mcp_call, response => iolist_to_binary(Body)}};
        {ok, {{_, Status, _}, _, _}} ->
            {error, {mcp_http_status, Status}};
        {error, Reason} ->
            {error, {mcp_error, Reason}}
    end.

%% --- Standard Callbacks --- %%

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Msg, State) -> {noreply, State}.

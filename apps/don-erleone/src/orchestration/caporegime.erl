-module(caporegime).
-include("records.hrl").
-behaviour(gen_server).
-behaviour(poolboy_worker).

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2]).

-ifdef(TEST).
-compile(export_all).
-endif.

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

    logger:info("Caporegime ~p executing mission ~p (intent=~s)", [self(), MissionId, Intent]),

    mission_store:update_status(MissionId, in_progress),

    Result = do_execute(MissionSpec, SubConfig),

    handle_result(MissionId, Result),
    notify_caller(MissionSpec, Result),

    {reply, Result, SubConfig}.

%% ------------------------------------------------------------------------
%% Internal: Execution Logic
%% ------------------------------------------------------------------------

do_execute(MissionSpec, SubConfig) ->
    #{id := MissionId, intent := Intent, prompt := Prompt, args := Args} = MissionSpec,
    try
        execute(Intent, Prompt, Args, SubConfig)
    catch
        Class:Error:Stack ->
            logger:error("Caporegime mission ~p crashed: ~p:~p~n~p", [MissionId, Class, Error, Stack]),
            {error, {crash, Error}}
    end.

execute(<<"k8s_deploy">>, Prompt, Args, SubConfig) ->
    SubPrompt = build_sub_prompt(<<"k8s_deploy">>, Prompt, Args),
    call_sub_model(SubPrompt, SubConfig);
execute(<<"check_mcp">>, Prompt, Args, SubConfig) ->
    case maps:get(<<"endpoint">>, Args, undefined) of
        undefined ->
            SubPrompt = build_sub_prompt(<<"check_mcp">>, Prompt, Args),
            call_sub_model(SubPrompt, SubConfig);
        URL when is_binary(URL) ->
            call_mcp_endpoint(URL, Args, SubConfig)
    end;
execute(<<"k8s_logs">>, _Prompt, Args, SubConfig) ->
    DefaultUrl = application:get_env(don_erleone, mcp_url, <<"http://kubernetes-mcp:8080/mcp">>),
    URL = maps:get(<<"endpoint">>, Args, DefaultUrl),
    call_mcp_endpoint(URL, Args, SubConfig);
execute(Intent, Prompt, Args, SubConfig) ->
    SubPrompt = build_sub_prompt(Intent, Prompt, Args),
    call_sub_model(SubPrompt, SubConfig).

%% ------------------------------------------------------------------------
%% AI & Protocol Handling
%% ------------------------------------------------------------------------

call_sub_model(SubPrompt, #sub_config{ollama_url = URL, model = Model, timeout = Timeout}) ->
    Opts = #{url => URL, model => Model, timeout => Timeout, stream => false},
    %% Fix: Handle the binary string returned by the Gun-based ollama_client
    case ollama_client:generate(SubPrompt, <<>>, [], Opts) of
        {ok, Response} when is_binary(Response) ->
            {ok, #{model => Model, response => Response}};
        Error ->
            Error
    end.

notify_caller(MissionSpec, {ok, Result}) ->
    case maps:get(cowboy_from, MissionSpec, undefined) of
        {CowboyPid, CowboyTag} ->
            MissionId = maps:get(id, MissionSpec, null),
            RawResponse = maps:get(response, Result, <<"Task executed successfully.">>),

            ResponseBin = if is_binary(RawResponse) -> RawResponse;
                             true -> iolist_to_binary(io_lib:format("~p", [RawResponse]))
                          end,

            FormattedResult = <<"\n\n---\n**Execution Result:**\n", ResponseBin/binary>>,

            %% Fix: Protocol sync with openai_handler stream_loop
            CowboyPid ! {CowboyTag, {chunk, FormattedResult, MissionId}},
            CowboyPid ! {CowboyTag, {done, <<>>, MissionId}},
            ok;
        _ ->
            ok
    end;
notify_caller(MissionSpec, {error, Reason}) ->
    case maps:get(cowboy_from, MissionSpec, undefined) of
        {CowboyPid, CowboyTag} ->
            CowboyPid ! {CowboyTag, {error, Reason}},
            ok;
        _ ->
            ok
    end.

%% ------------------------------------------------------------------------
%% MCP / External
%% ------------------------------------------------------------------------

call_mcp_endpoint(URL, Args, Config) ->
    RequestBody = build_mcp_payload(Args),
    do_mcp_request(URL, RequestBody, Config).

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

%% ------------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------------

handle_result(MissionId, {ok, Data}) ->
    mission_store:complete_mission(MissionId, Data),
    logger:info("Mission ~p completed", [MissionId]);
handle_result(MissionId, {error, Reason}) ->
    mission_store:fail_mission(MissionId, Reason),
    logger:warning("Mission ~p failed: ~p", [MissionId, Reason]).

build_sub_prompt(<<"k8s_deploy">>, Prompt, Args) ->
    iolist_to_binary([<<"You are a Kubernetes deployment sub-agent.\n">>,
                      <<"Generate a valid YAML manifest for the following request.\n">>,
                      <<"Request: ">>, Prompt, <<"\n">>,
                      <<"Arguments: ">>, jsx:encode(Args), <<"\n">>,
                      <<"Respond with JSON: {\"manifest\": \"<yaml>\", \"status\": \"ready\"}">>]);
build_sub_prompt(<<"check_mcp">>, Prompt, _Args) ->
    iolist_to_binary([<<"You are an infrastructure status sub-agent.\n">>,
                      <<"Assess the following request and provide a status report.\n">>,
                      <<"Request: ">>, Prompt, <<"\n">>,
                      <<"Respond with JSON: {\"status\": \"...\", \"details\": \"...\"}">>]);
build_sub_prompt(Intent, Prompt, Args) ->
    iolist_to_binary([<<"You are a sub-agent executing a delegated task.\n">>,
                      <<"Task intent: ">>, Intent, <<"\n">>,
                      <<"Request: ">>, Prompt, <<"\n">>,
                      <<"Arguments: ">>, jsx:encode(Args), <<"\n">>,
                      <<"Respond with JSON containing 'result' and 'status' fields.">>]).

build_mcp_payload(Args) ->
    jsx:encode(maps:without([<<"endpoint">>], Args)).

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Msg, State) -> {noreply, State}.
-module(the_front).
-behaviour(gen_server).

-export([
    start_link/0,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2
]).

-define(LISTENER_REF, http_frontend_listener).

%% ------------------------------------------------------------------------
%% Lifecycle
%% ------------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    %% Ensure a clean start by stopping any ghost listeners
    _ = cowboy:stop_listener(?LISTENER_REF),

    case start_http_listener() of
        {ok, _Pid} ->
            logger:info("The Front (HTTP) is operational on port 8080"),
            {ok, #{}};
        {error, Reason} ->
            {stop, {cowboy_start_failed, Reason}}
    end.

terminate(_Reason, _State) ->
    cowboy:stop_listener(?LISTENER_REF).

%% ------------------------------------------------------------------------
%% HTTP Configuration (The "Functional" Chunks)
%% ------------------------------------------------------------------------

start_http_listener() ->
    Dispatch = build_dispatch_rules(),
    Port = application:get_env(don_erleone, http_port, 8080),
    
    cowboy:start_clear(
        ?LISTENER_REF,
        [{port, Port}],
        #{
            env => #{dispatch => Dispatch},
            %% 15 minute idle timeout for long-running LLM streams
            idle_timeout => 900000 
        }
    ).

build_dispatch_rules() ->
    cowboy_router:compile([
        {'_', [
            {"/v1/chat/completions", openai_handler, []},
            {"/v1/models",           models_handler, []},
            {"/health",              health_handler, []}
        ]}
    ]).

%% ------------------------------------------------------------------------
%% Standard Callbacks
%% ------------------------------------------------------------------------

handle_call(_Req, _From, State) -> {reply, ok, State}.
handle_cast(_Msg, State)        -> {noreply, State}.
handle_info(_Msg, State)        -> {noreply, State}.
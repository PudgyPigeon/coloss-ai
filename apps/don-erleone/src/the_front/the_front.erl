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

start_link() ->
    gen_server:start_link(
        {local, ?MODULE},
        ?MODULE,
        [],
        []
    ).

init([]) ->
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/v1/chat/completions", openai_handler, []},
            {"/health", health_handler, []}
        ]}
    ]),

    %% Stop any existing listener before starting (crash recovery safety)
    _ = cowboy:stop_listener(http_frontend_listener),

    {ok, _} = cowboy:start_clear(
        http_frontend_listener,
        [{port, 8080}],
        #{env => #{dispatch => Dispatch, idle_timeout => 300000}}
    ),
    logger:info("The Front (HTTP) is active on port 8080"),
    {ok, #{}}.

handle_call(_Req, _From, State) -> {reply, ok, State}.

handle_cast(_Msg, State) -> {noreply, State}.

handle_info(_Msg, State) -> {noreply, State}.

terminate(_Reason, _State) ->
    cowboy:stop_listener(http_frontend_listener).

-module(hello_api).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    Dispatch =
        cowboy_router:compile([{'_',
                                [{"/v1/chat/completions", openai_handler, []},
                                 {"/v1/models", models_handler, []}]}]),
    {ok, _} =
        cowboy:start_clear(my_http_listener, [{port, 8080}], #{env => #{dispatch => Dispatch}}),
    hello_api_sup:start_link().

stop(_State) ->
    ok.

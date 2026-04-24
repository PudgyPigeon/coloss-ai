-module(health_handler).
-export([init/2]).

init(Req0, State) ->
    Body = jsx:encode(#{<<"status">> => <<"ok">>}),
    Req = cowboy_req:reply(
        200,
        #{<<"content-type">> => <<"application/json">>},
        Body,
        Req0
    ),
    {ok, Req, State}.

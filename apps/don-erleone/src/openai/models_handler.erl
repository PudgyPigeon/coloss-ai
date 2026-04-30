-module(models_handler).
-export([init/2]).

init(Req0, State) ->
    Models = [
        #{
            <<"id">> => <<"consigliere">>,
            <<"object">> => <<"model">>,
            <<"created">> => 1677610602,
            <<"owned_by">> => <<"don-erleone">>
        }
    ],
    RespBody = jsx:encode(#{
        <<"object">> => <<"list">>,
        <<"data">> => Models
    }),
    Req = cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, RespBody, Req0),
    {ok, Req, State}.

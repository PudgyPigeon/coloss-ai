%% <--- Add this
-module(openai_handler).

%% <--- Add this
-export([init/2]).

init(Req0, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Json = jsx:decode(Body, [return_maps]),

    %% Extract the model name from the JSON body
    Model = maps:get(<<"model">>, Json, <<"default">>),

    %% API triggers the supervisor to spawn the logic
    {ok, _Pid} = agent_sup:start_agent(Model),

    Response =
        #{<<"id">> => <<"cmpl-", Model/binary>>,
          <<"object">> => <<"chat.completion">>,
          <<"created">> => erlang:system_time(seconds),
          <<"model">> => Model,
          <<"choices">> =>
              [#{<<"message">> =>
                     #{<<"role">> => <<"assistant">>,
                       <<"content">> => <<"Orchestrating agent: ", Model/binary>>},
                 <<"finish_reason">> => <<"stop">>}]},

    Req = cowboy_req:reply(200,
                           #{<<"content-type">> => <<"application/json">>},
                           jsx:encode(Response),
                           Req1),
    {ok, Req, State}.

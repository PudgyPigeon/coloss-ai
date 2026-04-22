-module(openai_handler).

-export([init/2]).

init(Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_body(Req0),

    try
        %% 1. Decode the incoming OpenAI-style JSON
        Decoded = jsx:decode(Body, [return_maps]),
        Messages = maps:get(<<"messages">> , Decoded),
        
        %% 2. Extract the actual prompt from the last message
        #{<<"content">> := Prompt} = lists:last(Messages),

        %% 3. Pass the raw prompt to the GPU backend via Consigliere
        %% We now expect {ok, Answer, Meta}
        case consigliere:handle_mission(Prompt) of
            {ok, Answer, Meta} ->
                %% Extract the mission ID for the frontend "Pending" logic
                %% If no mission was logged, this becomes the atom 'null'
                MissionId = maps:get(mission_id, Meta, null),
                IdStr = case MissionId of
                    null -> <<"null">>;
                    _    -> iolist_to_binary(io_lib:format("~p", [MissionId]))
                end,
                Resp = jsx:encode(#{
                    <<"choices">> => [
                        #{<<"message">> => #{
                            <<"role">> => <<"assistant">>,
                            <<"content">> => Answer
                        }}
                    ],
                    <<"mission_id">> => IdStr
                }),

                {ok, cowboy_req:reply(
                    200,
                    #{<<"content-type">> => <<"application/json">>},
                    Resp,
                    Req
                ), State};

            {error, Reason} ->
                io:format("Alert: Consigliere failed mission: ~p~n", [Reason]),
                ErrorResp = jsx:encode(#{<<"error">> => iolist_to_binary(io_lib:format("~p", [Reason]))}),
                {ok, cowboy_req:reply(500, #{<<"content-type">> => <<"application/json">>}, ErrorResp, Req), State}
        end
    catch
        _:Error ->
            io:format("Alert: OpenAI Handler crash: ~p~n", [Error]),
            {ok, cowboy_req:reply(400, Req), State}
    end.
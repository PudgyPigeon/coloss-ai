-module(openai_handler).
-export([init/2]).

init(Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_body(Req0),
    
    try
        %% 1. Decode the incoming OpenAI-style JSON
        Decoded = jsx:decode(Body, [return_maps]),
        Messages = maps:get(<<"messages">>, Decoded),

        %% 2. Extract the actual prompt from the last message
        #{<<"content">> := Prompt} = lists:last(Messages),

        %% 3. Pass the raw prompt to the 5080 backend via Consigliere
        case consigliere:handle_mission(Prompt) of
            {ok, Answer} ->
                %% Answer should be a binary string here
                Resp = jsx:encode(#{
                    <<"choices">> => [
                        #{<<"message">> => #{
                            <<"role">> => <<"assistant">>,
                            <<"content">> => Answer
                        }}
                    ]
                }),
                {ok, cowboy_req:reply(200, 
                    #{<<"content-type">> => <<"application/json">>}, Resp, Req), State};

            {error, Reason} ->
                %% Log the specific infrastructure failure for SRE visibility
                io:format("SRE Alert: Consigliere failed mission: ~p~n", [Reason]),
                {ok, cowboy_req:reply(500, Req), State}
        end
    catch
        _:Error ->
            io:format("SRE Alert: OpenAI Handler crash: ~p~n", [Error]),
            {ok, cowboy_req:reply(400, Req), State}
    end.
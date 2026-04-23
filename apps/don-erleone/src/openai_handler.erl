-module(openai_handler).
-export([init/2]).

-define(JSON_TYPE, #{<<"content-type">> => <<"application/json">>}).

init(Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_body(Req0),
    try
        #{<<"messages">> := Messages} = jsx:decode(Body, [return_maps]),
        #{<<"content">> := Prompt} = lists:last(Messages),

        {PeerIP, _} = cowboy_req:peer(Req),
        SessionId = iolist_to_binary(io_lib:format("~p", [PeerIP])),

        %% 1. Define 'From'. In a plain process, this is {Pid, Tag}
        Tag = make_ref(),
        From = {self(), Tag},

        %% 2. Tell the Consigliere to start the work
        consigliere:handle_mission(SessionId, Prompt, From),

        %% 3. Wait for the worker to call gen_server:reply (which is just a ! message)
%% ... same logic as before ...
        receive
            {Tag, Result} -> 
                handle_mission_response(Result, Req, State);
            Unexpected -> 
                io:format("SRE DEBUG: Received garbage: ~p~n", [Unexpected]),
                handle_mission_response({error, internal_plumbing_error}, Req, State)
        after 120000 -> 
            handle_mission_response({error, timeout}, Req, State)
        end

    catch
        _:Error:Stack ->
            io:format("CRITICAL: Handler crash: ~p~nStack: ~p~n", [Error, Stack]),
            {ok, cowboy_req:reply(400, Req0), State}
    end.

handle_mission_response({ok, Answer, Meta}, Req, State) ->
    MissionId = maps:get(mission_id, Meta, null),

    IdStr =
        case MissionId of
            null -> <<"null">>;
            _ -> iolist_to_binary(io_lib:format("~p", [MissionId]))
        end,

    Resp = jsx:encode(#{
        <<"choices">> => [
            #{
                <<"message">> => #{
                    <<"role">> => <<"assistant">>,
                    <<"content">> => Answer
                }
            }
        ],
        <<"mission_id">> => IdStr
    }),

    {ok, cowboy_req:reply(200, ?JSON_TYPE, Resp, Req), State};
handle_mission_response({error, Reason}, Req, State) ->
    io:format("ALERT: Consigliere failed: ~p~n", [Reason]),
    ErrorResp = jsx:encode(#{
        <<"error">> => iolist_to_binary(io_lib:format("~p", [Reason]))
    }),
    {ok, cowboy_req:reply(500, ?JSON_TYPE, ErrorResp, Req), State}.

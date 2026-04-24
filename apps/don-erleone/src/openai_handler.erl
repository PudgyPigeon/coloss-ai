-module(openai_handler).
-export([init/2]).

-define(JSON_TYPE, #{<<"content-type">> => <<"application/json">>}).

-ifdef(TEST).
-compile(export_all).
-endif.

init(Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_body(Req0),
    case parse_request(Body, Req) of
        {ok, SessionId, Prompt} ->
            do_mission(SessionId, Prompt, Req, State);
        {error, ErrorInfo} ->
            handle_bad_request(ErrorInfo, Req, State)
    end.

%% --- Internal Helpers ---

parse_request(Body, Req) ->
    try
        #{<<"messages">> := Messages} = jsx:decode(Body, [return_maps]),
        #{<<"content">> := Prompt} = lists:last(Messages),
        {PeerIP, _} = cowboy_req:peer(Req),
        SessionId = iolist_to_binary(io_lib:format("~p", [PeerIP])),
        {ok, SessionId, Prompt}
    catch
        _:Error:Stack ->
            {error, {Error, Stack}}
    end.

do_mission(SessionId, Prompt, Req, State) ->
    %% Create a unique tag for this request so we can receive the reply
    Tag = make_ref(),
    From = {self(), Tag},

    %% Dispatch to the consigliere pool (returns immediately)
    consigliere:handle_mission(SessionId, Prompt, From),

    %% Block until the worker sends the result back
    receive
        {Tag, Result} ->
            handle_mission_response(Result, Req, State)
    after 120000 ->
        handle_mission_response({error, timeout}, Req, State)
    end.

handle_bad_request({Error, Stack}, Req, State) ->
    logger:error("Handler crash: ~p~nStack: ~p", [Error, Stack]),
    ErrorBody = jsx:encode(#{
        <<"error">> => #{
            <<"message">> => <<"Invalid request">>,
            <<"type">> => <<"server_error">>
        }
    }),
    {ok, cowboy_req:reply(400, ?JSON_TYPE, ErrorBody, Req), State}.

handle_mission_response({ok, Answer, Meta}, Req, State) ->
    MissionId = maps:get(mission_id, Meta, null),
    Resp = build_success_response(Answer, MissionId),
    {ok, cowboy_req:reply(200, ?JSON_TYPE, Resp, Req), State};
handle_mission_response({error, Reason}, Req, State) ->
    logger:warning("Consigliere failed: ~p", [Reason]),
    ErrorResp = build_error_response(Reason),
    {ok, cowboy_req:reply(500, ?JSON_TYPE, ErrorResp, Req), State}.

build_success_response(Answer, MissionId) ->
    IdStr =
        case MissionId of
            null -> <<"null">>;
            _ -> iolist_to_binary(io_lib:format("~p", [MissionId]))
        end,
    jsx:encode(#{
        <<"choices">> => [
            #{
                <<"message">> => #{
                    <<"role">> => <<"assistant">>,
                    <<"content">> => Answer
                }
            }
        ],
        <<"mission_id">> => IdStr
    }).

build_error_response(Reason) ->
    jsx:encode(#{
        <<"error">> => #{
            <<"message">> => iolist_to_binary(io_lib:format("~p", [Reason])),
            <<"type">> => <<"consigliere_error">>
        }
    }).

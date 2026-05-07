-module(de_openai_formatter).
-export([
    stream_chunk/3, 
    stream_done/2, 
    stream_error/3, 
    build_success/2, 
    build_error/1
]).

%% ===================================================================
%% Streaming (SSE) Builders
%% ===================================================================

stream_chunk(Req, Content, MissionId) ->
    IdStr = mission_id_str(MissionId),
    ChunkData = #{
        <<"id">> => IdStr,
        <<"object">> => <<"chat.completion.chunk">>,
        <<"choices">> => [#{
            <<"index">> => 0,
            <<"delta">> => #{<<"content">> => Content},
            <<"finish_reason">> => null
        }]
    },
    Payload = iolist_to_binary(["data: ", jsx:encode(ChunkData), "\n\n"]),
    cowboy_req:stream_body(Payload, nofin, Req).

stream_done(Req, MissionId) ->
    IdStr = mission_id_str(MissionId),
    FinishData = #{
        <<"id">> => IdStr,
        <<"object">> => <<"chat.completion.chunk">>,
        <<"choices">> => [#{
            <<"index">> => 0,
            <<"delta">> => #{},
            <<"finish_reason">> => <<"stop">>
        }]
    },
    FinishPayload = iolist_to_binary(["data: ", jsx:encode(FinishData), "\n\n"]),
    cowboy_req:stream_body(FinishPayload, nofin, Req),
    cowboy_req:stream_body(<<"data: [DONE]\n\n">>, fin, Req).

stream_error(Req, Reason, MissionId) ->
    ErrorText = iolist_to_binary([<<"\n\n---\n**System Error:**\n">>, iolist_to_binary(io_lib:format("~p", [Reason]))]),
    stream_chunk(Req, ErrorText, MissionId),
    stream_done(Req, MissionId).

%% ===================================================================
%% Non-Streaming (JSON) Builders
%% ===================================================================

build_success(Answer, MissionId) ->
    IdStr = mission_id_str(MissionId),
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

build_error(Reason) ->
    jsx:encode(#{
        <<"error">> => #{
            <<"message">> => iolist_to_binary(io_lib:format("~p", [Reason])),
            <<"type">> => <<"de_consigliere_error">>
        }
    }).

%% ===================================================================
%% Internal Helpers
%% ===================================================================

mission_id_str(null) -> <<"null">>;
mission_id_str(Id) -> iolist_to_binary(io_lib:format("~p", [Id])).
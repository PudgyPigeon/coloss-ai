-module(openai_handler).
-export([init/2]).

-define(JSON_TYPE, #{<<"content-type">> => <<"application/json">>}).
-define(SSE_TYPE, #{
    <<"content-type">> => <<"text/event-stream">>,
    <<"cache-control">> => <<"no-cache">>,
    <<"connection">> => <<"keep-alive">>
}).

init(Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_body(Req0),
    case parse_request(Body, Req) of
        {ok, SessionId, Prompt, Stream} ->
            do_mission(SessionId, Prompt, Stream, Req, State);
        {error, ErrorInfo} ->
            handle_bad_request(ErrorInfo, Req, State)
    end.

parse_request(Body, Req) ->
    try
        Decoded = jsx:decode(Body, [return_maps]),
        #{<<"messages">> := Messages} = Decoded,
        #{<<"content">> := Prompt} = lists:last(Messages),
        Stream = maps:get(<<"stream">>, Decoded, false),
        {PeerIP, _} = cowboy_req:peer(Req),
        SessionId = iolist_to_binary(io_lib:format("~p", [PeerIP])),
        {ok, SessionId, Prompt, Stream}
    catch
        _:Error:Stack ->
            {error, {Error, Stack}}
    end.

%% ===================================================================
%% Streaming Mode + Non-Streaming
%% ===================================================================

do_mission(SessionId, Prompt, true, Req, State) ->
    Tag = make_ref(),
    From = {self(), Tag},
    consigliere:handle_mission(SessionId, Prompt, From),
    
    Req1 = cowboy_req:stream_reply(200, ?SSE_TYPE, Req),
    stream_loop(Req1, Tag, null, State);

%% ===================================================================
%% Non-Streaming Mode
%% ===================================================================

do_mission(SessionId, Prompt, false, Req, State) ->
    Tag = make_ref(),
    From = {self(), Tag},
    consigliere:handle_mission(SessionId, Prompt, From),

    receive
        {Tag, {done, FinalContent, MissionId}} ->
            RespBody = openai_formatter:build_success(FinalContent, MissionId),
            {ok, cowboy_req:reply(200, ?JSON_TYPE, RespBody, Req), State};
            
        {Tag, {error, Reason}} ->
            logger:warning("Mission failed: ~p", [Reason]),
            ErrorBody = openai_formatter:build_error(Reason),
            {ok, cowboy_req:reply(500, ?JSON_TYPE, ErrorBody, Req), State}
            
    after 120000 ->
        logger:error("Mission timeout for tag: ~p", [Tag]),
        ErrorBody = openai_formatter:build_error(timeout),
        {ok, cowboy_req:reply(504, ?JSON_TYPE, ErrorBody, Req), State}
    end.

stream_loop(Req, Tag, LastMissionId, State) ->
    receive
        {Tag, {chunk, Content, MissionId}} ->
            openai_formatter:stream_chunk(Req, Content, MissionId),
            %% Recursively wait for the next chunk
            stream_loop(Req, Tag, MissionId, State);
            
        {Tag, {done, _FinalContent, MissionId}} ->
            openai_formatter:stream_done(Req, MissionId),
            {ok, Req, State};
            
        {Tag, {error, Reason}} ->
            logger:warning("Streaming failed: ~p", [Reason]),
            openai_formatter:stream_error(Req, Reason, LastMissionId),
            {ok, Req, State}
            
    after 120000 ->
        logger:error("Streaming timeout for tag: ~p", [Tag]),
        openai_formatter:stream_error(Req, timeout, LastMissionId),
        {ok, Req, State}
    end.

handle_bad_request({Error, Stack}, Req, State) ->
    logger:error("Invalid request payload: ~p~nStack: ~p", [Error, Stack]),
    ErrorBody = openai_formatter:build_error(<<"Invalid JSON payload">>),
    {ok, cowboy_req:reply(400, ?JSON_TYPE, ErrorBody, Req), State}.
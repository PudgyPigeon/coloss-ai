-module(openai_handler).
-export([init/2]).

-define(JSON_TYPE, #{<<"content-type">> => <<"application/json">>}).
-define(SSE_TYPE, #{
    <<"content-type">> => <<"text/event-stream stream">>,
    <<"cache-control">> => <<"no-cache">>,
    <<"connection">> => <<"keep-alive">>
}).

%% ------------------------------------------------------------------------
%% Entry Point
%% ------------------------------------------------------------------------

init(Req0, State) ->
    StartTime = erlang:system_time(microsecond),
    Path = cowboy_req:path(Req0),
    telemetry:execute([don_erleone, http, request, start], #{time => StartTime}, #{path => Path}),
    
    {ok, Body, Req} = cowboy_req:read_body(Req0),
    case parse_incoming_request(Body, Req) of
        {ok, Params} ->
            Result = handle_mission_request(Params, Req, State),
            telemetry:execute([don_erleone, http, request, stop], #{duration => erlang:system_time(microsecond) - StartTime}, #{path => Path, success => true}),
            Result;
        {error, Reason} ->
            telemetry:execute([don_erleone, http, request, stop], #{duration => erlang:system_time(microsecond) - StartTime}, #{path => Path, success => false, error => Reason}),
            handle_bad_request(Reason, Req, State)
    end.

%% ------------------------------------------------------------------------
%% Mission Orchestration
%% ------------------------------------------------------------------------

handle_mission_request(#{stream := true} = Params, Req, State) ->
    {SessionId, Prompt} = extract_basics(Params),
    Tag = make_ref(),
    
    %% Async hand-off to the Consigliere
    consigliere:handle_mission(SessionId, Prompt, {self(), Tag}),
    
    %% Prepare the SSE stream
    Req1 = cowboy_req:stream_reply(200, ?SSE_TYPE, Req),
    run_stream_loop(Req1, Tag, null, State);

handle_mission_request(#{stream := false} = Params, Req, State) ->
    {SessionId, Prompt} = extract_basics(Params),
    Tag = make_ref(),
    
    consigliere:handle_mission(SessionId, Prompt, {self(), Tag}),
    wait_for_sync_result(Req, Tag, SessionId, State).

%% ------------------------------------------------------------------------
%% Sync Response Loop
%% ------------------------------------------------------------------------

wait_for_sync_result(Req, Tag, SessionId, State) ->
    receive
        {Tag, {done, Content, Mid}} ->
            send_json_reply(200, openai_formatter:build_success(Content, Mid), Req, State);
        
        {Tag, {error, Reason}} ->
            logger:error(#{event => sync_mission_failed, session_id => SessionId, error => Reason}),
            send_json_reply(500, openai_formatter:build_error(Reason), Req, State)
            
    after 120000 ->
        logger:error(#{event => sync_mission_timeout, session_id => SessionId}),
        send_json_reply(504, openai_formatter:build_error(timeout), Req, State)
    end.

%% ------------------------------------------------------------------------
%% Async Stream Loop
%% ------------------------------------------------------------------------

run_stream_loop(Req, Tag, LastMid, State) ->
    receive
        {Tag, {chunk, Content, Mid}} ->
            openai_formatter:stream_chunk(Req, Content, Mid),
            run_stream_loop(Req, Tag, Mid, State);
            
        {Tag, {done, Content, Mid}} ->
            safe_stream_finish(Req, Content, Mid, State);
            
        {Tag, {error, Reason}} ->
            safe_stream_error(Req, Reason, LastMid, State);

        {Tag, {execution_complete, Result}} ->
            handle_late_execution(Req, Result, LastMid, State);

        _Unexpected ->
            run_stream_loop(Req, Tag, LastMid, State)
            
    after 120000 ->
        safe_stream_error(Req, timeout, LastMid, State)
    end.

%% ------------------------------------------------------------------------
%% Logic Chunks (The "Functional" bits)
%% ------------------------------------------------------------------------

parse_incoming_request(Body, Req) ->
    try
        Decoded = jsx:decode(Body, [return_maps]),
        #{<<"messages">> := Messages} = Decoded,
        #{<<"content">> := Prompt} = lists:last(Messages),
        
        {PeerIP, _} = cowboy_req:peer(Req),
        
        {ok, #{
            session_id => to_bin_ip(PeerIP),
            prompt => Prompt,
            stream => maps:get(<<"stream">>, Decoded, false)
        }}
    catch
        _:E:S -> {error, {E, S}}
    end.

extract_basics(#{session_id := Sid, prompt := P}) -> {Sid, P}.

send_json_reply(Status, Body, Req, State) ->
    {ok, cowboy_req:reply(Status, ?JSON_TYPE, Body, Req), State}.

handle_bad_request(ErrorInfo, Req, State) ->
    logger:error(#{event => bad_request, error => ErrorInfo}),
    Body = openai_formatter:build_error(<<"Invalid JSON payload">>),
    send_json_reply(400, Body, Req, State).

%% ------------------------------------------------------------------------
%% Stream Helpers
%% ------------------------------------------------------------------------

safe_stream_finish(Req, Content, Mid, State) ->
    try
        openai_formatter:stream_chunk(Req, Content, Mid),
        openai_formatter:stream_done(Req, Mid),
        {ok, Req, State}
    catch
        _:E -> safe_stream_error(Req, E, Mid, State)
    end.

safe_stream_error(Req, Reason, Mid, State) ->
    try openai_formatter:stream_error(Req, Reason, Mid) catch _:_ -> ok end,
    {ok, Req, State}.

handle_late_execution(Req, {ok, #{response := C, id := Mid}}, _LastMid, State) ->
    safe_stream_finish(Req, C, Mid, State);
handle_late_execution(Req, {error, R}, LastMid, State) ->
    safe_stream_error(Req, R, LastMid, State).

to_bin_ip(IP) -> iolist_to_binary(io_lib:format("~p", [IP])).
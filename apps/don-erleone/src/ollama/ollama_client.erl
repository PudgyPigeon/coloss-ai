%% @doc Shared HTTP client for Ollama API calls via Gun.
-module(ollama_client).

-export([generate/3, generate/4, generate/5, generate_with_tools/5]).

-ifdef(TEST).
-compile(export_all).
-endif.

%% ------------------------------------------------------------------------
%% API
%% ------------------------------------------------------------------------

generate(Prompt, System, Opts) ->
    generate(Prompt, System, [], Opts, undefined).

generate(Prompt, System, Context, Opts) ->
    generate(Prompt, System, Context, Opts, undefined).

generate(Prompt, System, Context, Opts, Callback) ->
    execute_request(Prompt, System, Context, [], Opts, Callback).

generate_with_tools(Prompt, System, Context, Tools, Opts) ->
    execute_request(Prompt, System, Context, Tools, Opts, undefined).

%% ------------------------------------------------------------------------
%% High-Level Request Flow
%% ------------------------------------------------------------------------

execute_request(Prompt, System, Context, Tools, Opts, Callback) ->
    %% SRE Fix: Using maps:get to avoid badmatch if Opts is not exactly a map 
    %% or is missing keys.
    URL     = maps:get(url, Opts),
    Model   = maps:get(model, Opts),
    Timeout = maps:get(timeout, Opts, 120000), %% Default to 120s
    Stream  = maps:get(stream, Opts, false),

    Payload  = build_payload(Model, Prompt, Context, System, Stream, Tools),
    Endpoint = resolve_chat_endpoint(URL),

    do_http_call(Endpoint, Payload, Timeout, Stream, Callback).

%% ------------------------------------------------------------------------
%% HTTP Execution (Gun Logic)
%% ------------------------------------------------------------------------

do_http_call(Endpoint, Payload, Timeout, IsStream, Callback) ->
    URI  = uri_string:parse(Endpoint),
    Host = maps:get(host, URI),
    Port = maps:get(port, URI, 80),
    Path = maps:get(path, URI),

    case gun:open(Host, Port, #{connect_timeout => 5000, protocols => [http]}) of
        {ok, ConnPid} ->
            try gun:await_up(ConnPid, 5000) of
                {ok, _} ->
                    Headers = [{<<"content-type">>, <<"application/json">>}],
                    StreamRef = gun:post(ConnPid, Path, Headers, Payload),
                    Result = stream_loop(ConnPid, StreamRef, Timeout, IsStream, <<>>, <<>>, Callback),
                    gun:close(ConnPid),
                    Result;
                {error, Reason} ->
                    gun:close(ConnPid),
                    {error, {connection_failed, Reason}}
            catch`
                _:_ -> gun:close(ConnPid), {error, connection_timeout}
            end;
        {error, Reason} ->
            {error, {open_failed, Reason}}
    end.

%% ------------------------------------------------------------------------
%% Stream State Machine
%% ------------------------------------------------------------------------

stream_loop(Conn, Ref, Tmo, IsStream, Buffer, Acc, CB) ->
    receive
        %% Response Metadata
        {gun_response, Conn, Ref, nofin, 200, _} ->
            stream_loop(Conn, Ref, Tmo, IsStream, Buffer, Acc, CB);
        
        {gun_response, Conn, Ref, _, Status, _} when Status >= 400 ->
            {error, {http_status, Status}};

        %% Data Ingress
        {gun_data, Conn, Ref, nofin, Data} ->
            handle_ongoing_data(Conn, Ref, Tmo, IsStream, <<Buffer/binary, Data/binary>>, Acc, CB);

        {gun_data, Conn, Ref, fin, Data} ->
            handle_final_data(<<Buffer/binary, Data/binary>>, IsStream, Acc, CB);

        %% Error states
        {gun_error, Conn, Ref, Reason} -> {error, {stream_err, Reason}};
        {gun_error, Conn, Reason}      -> {error, {gun_err, Reason}};
        {gun_down, Conn, _, _, _, _}   -> {error, connection_closed}
    after Tmo ->
        {error, timeout}
    end.

%% ------------------------------------------------------------------------
%% Data Processing Logic
%% ------------------------------------------------------------------------

handle_ongoing_data(Conn, Ref, Tmo, true, Buffer, Acc, CB) ->
    {NextBuf, NewAcc} = process_ndjson_lines(Buffer, Acc, CB),
    stream_loop(Conn, Ref, Tmo, true, NextBuf, NewAcc, CB);
handle_ongoing_data(Conn, Ref, Tmo, false, Buffer, Acc, CB) ->
    stream_loop(Conn, Ref, Tmo, false, Buffer, Acc, CB).

handle_final_data(FinalBody, true, Acc, CB) ->
    {Remainder, TempAcc} = process_ndjson_lines(FinalBody, Acc, CB),
    {ok, finalize_json(Remainder, TempAcc, CB)};
handle_final_data(FinalBody, false, Acc, CB) ->
    case finalize_json(FinalBody, Acc, CB) of
        {error, _} = Err -> Err;
        Result -> {ok, Result}
    end.

process_ndjson_lines(Buffer, Acc, CB) ->
    case binary:split(Buffer, <<"\n">>) of
        [Line, Rest] ->
            NewAcc = finalize_json(Line, Acc, CB),
            process_ndjson_lines(Rest, NewAcc, CB);
        [Remainder] ->
            {Remainder, Acc}
    end.

finalize_json(<<>>, Acc, _) -> Acc;
finalize_json(Line, Acc, CB) ->
    try jsx:decode(Line, [return_maps]) of
        #{<<"message">> := Msg} -> process_ollama_msg(Msg, Acc, CB);
        #{<<"error">> := Err}   -> {error, {ollama_error, Err}};
        _                       -> Acc
    catch _:_ -> Acc end.

process_ollama_msg(#{<<"content">> := C} = Msg, Acc, CB) ->
    maybe_callback(CB, C),
    accumulate_text(Acc, Msg, C);
process_ollama_msg(Msg, _Acc, _CB) ->
    Msg.

%% ------------------------------------------------------------------------
%% Construction & Normalization
%% ------------------------------------------------------------------------

build_payload(Model, Prompt, Context, System, Stream, Tools) ->
    SysBin = to_bin(System),
    SysMsgs = if SysBin =:= <<>> -> []; true -> [#{<<"role">> => <<"system">>, <<"content">> => SysBin}] end,
    
    PromptBin = to_bin(Prompt),
    UserMsgs = if PromptBin =:= <<>> -> []; true -> [#{<<"role">> => <<"user">>, <<"content">> => PromptBin}] end,
    
    FullMessages = SysMsgs ++ Context ++ UserMsgs,
    
    Base = #{
        <<"model">>    => to_bin(Model),
        <<"messages">> => FullMessages,
        <<"stream">>   => Stream
    },
    jsx:encode(maybe_add_tools(Base, Tools)).

resolve_chat_endpoint(URL) ->
    L = to_list(URL),
    lists:flatten(string:replace(L, "/api/generate", "/api/chat")).

maybe_add_tools(Payload, []) -> Payload;
maybe_add_tools(Payload, Tools) -> Payload#{<<"tools">> => Tools}.

maybe_callback(undefined, _) -> ok;
maybe_callback(CB, Content)  -> CB(Content).

accumulate_text(<<>>, Msg, _C) -> Msg;
accumulate_text(Acc, _Msg, C) when is_binary(Acc) -> <<Acc/binary, C/binary>>;
accumulate_text(_Acc, Msg, _C) -> Msg.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> list_to_binary(L);
to_bin(Any) -> iolist_to_binary(io_lib:format("~p", [Any])).

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L.
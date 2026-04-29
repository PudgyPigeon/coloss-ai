%% @doc Shared HTTP client for Ollama API calls via Gun.
-module(ollama_client).

-export([generate/3, generate/4, generate/5]).

-ifdef(TEST).
-compile(export_all).
-endif.

generate(Prompt, SystemPrompt, Opts) ->
    generate(Prompt, SystemPrompt, [], Opts, undefined).

generate(Prompt, SystemPrompt, PrevContext, Opts) ->
    generate(Prompt, SystemPrompt, PrevContext, Opts, undefined).

%% @doc Call Ollama with an optional ChunkCallback function for streaming
generate(Prompt, SystemPrompt, PrevContext, Opts, ChunkCallback) ->
    #{url := URL, model := Model, timeout := Timeout} = Opts,
    Stream = maps:get(stream, Opts, false),
    
    Payload = build_payload(Model, Prompt, PrevContext, SystemPrompt, Stream),
    SafeURL = to_list(URL),
    ChatURL = string:replace(SafeURL, "/api/generate", "/api/chat"),
    
    do_request(lists:flatten(ChatURL), Payload, Timeout, ChunkCallback).

%% --- Internal HTTP & State Machine ---

do_request(ChatURL, Payload, Timeout, ChunkCallback) ->
    %% Parse the URL to get Host, Port, and Path
    URI = uri_string:parse(ChatURL),
    Host = maps:get(host, URI),
    Port = maps:get(port, URI, 80),
    Path = maps:get(path, URI),

    %% 1. Open the async connection
    {ok, ConnPid} = gun:open(Host, Port, #{connect_timeout => 5000}),
    
    case gun:await_up(ConnPid, 5000) of
        {ok, _Protocol} ->
            Headers = [{<<"content-type">>, <<"application/json">>}],
            %% 2. Fire the POST request (this returns a Stream Reference ID)
            StreamRef = gun:post(ConnPid, Path, Headers, Payload),
            
            %% 3. Enter the receive loop to catch the streaming response
            Result = stream_loop(ConnPid, StreamRef, Timeout, <<>>, <<>>, ChunkCallback),
            
            %% 4. Clean up the connection when finished
            gun:close(ConnPid),
            Result;
            
        {error, Reason} ->
            gun:close(ConnPid),
            {error, {connection_failed, Reason}}
    end.

stream_loop(ConnPid, StreamRef, Timeout, Buffer, AccText, ChunkCallback) ->
    receive
        %% Catch the initial HTTP headers
        {gun_response, ConnPid, StreamRef, fin, Status, _Headers} ->
            {error, {http_status, Status}};
        {gun_response, ConnPid, StreamRef, nofin, 200, _Headers} ->
            %% HTTP 200 OK. The body will follow as gun_data messages. Loop!
            stream_loop(ConnPid, StreamRef, Timeout, Buffer, AccText, ChunkCallback);
        {gun_response, ConnPid, StreamRef, nofin, Status, _Headers} ->
            {error, {http_status, Status}};

        %% Catch the streaming body chunks
        {gun_data, ConnPid, StreamRef, nofin, Data} ->
            %% Append new data to buffer and extract any complete JSON lines
            {NextBuffer, NewAccText} = process_buffer(<<Buffer/binary, Data/binary>>, AccText, ChunkCallback),
            stream_loop(ConnPid, StreamRef, Timeout, NextBuffer, NewAccText, ChunkCallback);

        %% Catch the final chunk
        {gun_data, ConnPid, StreamRef, fin, Data} ->
            FinalBuffer = <<Buffer/binary, Data/binary>>,
            {LastRemainder, TempAccText} = process_buffer(FinalBuffer, AccText, ChunkCallback),
            
            %% Parse whatever is left in the buffer (in case it lacked a trailing newline)
            FinalAccText = process_single_json(LastRemainder, TempAccText, ChunkCallback),
            {ok, FinalAccText};

        {gun_error, ConnPid, StreamRef, Reason} ->
            {error, Reason};
        {gun_down, ConnPid, _, _, _, _} ->
            {error, connection_closed}
            
    after Timeout ->
        {error, timeout}
    end.

%% --- NDJSON Buffer Logic ---

process_buffer(Buffer, AccText, ChunkCallback) ->
    case binary:split(Buffer, <<"\n">>) of
        [Line, Rest] ->
            NewAcc = process_single_json(Line, AccText, ChunkCallback),
            %% Recursively process the rest of the buffer
            process_buffer(Rest, NewAcc, ChunkCallback);
        [Remainder] ->
            %% No newline found. Wait for the next chunk of data.
            {Remainder, AccText}
    end.

process_single_json(<<>>, AccText, _) -> 
    AccText;
process_single_json(JSONLine, AccText, ChunkCallback) ->
    try jsx:decode(JSONLine, [return_maps]) of
        #{<<"message">> := #{<<"content">> := Content}} ->
            %% If a callback was provided, fire it instantly
            if ChunkCallback =/= undefined -> ChunkCallback(Content);
               true -> ok
            end,
            %% Append to the full accumulated text
            <<AccText/binary, Content/binary>>;
        _ -> 
            AccText
    catch 
        _:_ -> AccText
    end.

%% --- Utility ---

build_payload(Model, Prompt, PrevContext, SystemPrompt, Stream) ->
    SystemMsg = #{<<"role">> => <<"system">>, <<"content">> => to_binary(SystemPrompt)},
    UserMsg = #{<<"role">> => <<"user">>, <<"content">> => to_binary(Prompt)},
    Messages = [SystemMsg | PrevContext] ++ [UserMsg],
    jsx:encode(#{
        <<"model">> => to_binary(Model),
        <<"messages">> => Messages,
        <<"format">> => <<"json">>,
        <<"stream">> => Stream
    }).

to_binary(B) when is_binary(B) -> B;
to_binary(L) when is_list(L) -> list_to_binary(L);
to_binary(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).
to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L.
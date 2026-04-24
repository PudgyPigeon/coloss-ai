%% @doc Shared HTTP client for Ollama API calls.
%% Used by both consigliere_worker (large model) and caporegime (sub-model).
-module(ollama_client).

-export([generate/3, generate/4]).

%% @doc Call Ollama with a prompt, system prompt, and previous context.
%% Used by the consigliere for the main reasoning call.
generate(Prompt, SystemPrompt, Opts) ->
    generate(Prompt, SystemPrompt, [], Opts).

%% @doc Call Ollama with prompt, system prompt, previous context, and options.
%% Opts is a map: #{url, model, timeout, stream}
generate(Prompt, SystemPrompt, PrevContext, Opts) ->
    #{url := URL, model := Model, timeout := Timeout} = Opts,
    Stream = maps:get(stream, Opts, false),
    Payload = build_payload(Model, Prompt, PrevContext, SystemPrompt, Stream),
    SafeURL = to_list(URL),
    do_request(SafeURL, Payload, Timeout).

%% --- Internal ---

build_payload(Model, Prompt, PrevContext, SystemPrompt, Stream) ->
    jsx:encode(#{
        <<"model">> => to_binary(Model),
        <<"prompt">> => to_binary(Prompt),
        <<"context">> => PrevContext,
        <<"system">> => to_binary(SystemPrompt),
        <<"format">> => <<"json">>,
        <<"stream">> => Stream
    }).

do_request(URL, Payload, Timeout) ->
    HttpOpts = [{timeout, Timeout}, {connect_timeout, 5000}],
    case httpc:request(post, {URL, [], "application/json", Payload}, HttpOpts, []) of
        {ok, {{_, 200, _}, _, Body}} ->
            {ok, jsx:decode(iolist_to_binary(Body), [return_maps])};
        {ok, {{_, Status, _}, _, _}} ->
            {error, {http_status, Status}};
        {error, Reason} ->
            {error, Reason}
    end.

to_binary(Data) ->
    case Data of
        B when is_binary(B) -> B;
        L when is_list(L) -> 
            case unicode:characters_to_binary(L) of
                Result when is_binary(Result) -> Result;
                _ -> list_to_binary(L) %% Fallback
            end;
        Other -> iolist_to_binary(io_lib:format("~p", [Other]))
    end.

to_list(Data) ->
    case Data of
        B when is_binary(B) -> binary_to_list(B);
        L when is_list(L) -> L
    end.

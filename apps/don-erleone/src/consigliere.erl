-module(consigliere).
-behaviour(gen_server).

-export([start_link/0, handle_mission/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(config, {
    ollama_url :: string(),
    model      :: string(),
    timeout    :: integer()
}).

%% --- API ---
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

handle_mission(Prompt) ->
    gen_server:call(?MODULE, {ollama, Prompt}, infinity).

%% --- Callbacks ---

init([]) ->
    %% 1. Fetch values with type-safe defaults
    ModelRaw   = application:get_env(don_erleone, ollama_model, "qwen3.5:9b"),
    URLRaw     = application:get_env(don_erleone, ollama_url, "http://localhost:11434/api/generate"),
    TimeoutRaw = application:get_env(don_erleone, timeout, 3600000),

    %% 2. Sanitizer: Strip typos and ghosts
    CleanStr = fun(S) -> 
        case is_list(S) or is_binary(S) of
            true ->
                C = re:replace(S, "[^a-zA-Z0-9\\.\\:\\/\\-_]", "", [global, {return, list}]),
                %% Handle 'bb' and 'ee' trailing ghosts
                case lists:suffix("ee", C) of true -> lists:droplast(C); false -> 
                case lists:suffix("bb", C) of true -> lists:droplast(C); false -> C end end;
            false -> S
        end
    end,

    %% 3. Type-safe timeout handling
    Timeout = case TimeoutRaw of
        T when is_integer(T) -> T;
        T when is_list(T); is_binary(T) ->
            list_to_integer(re:replace(T, "[^0-9]", "", [global, {return, list}]));
        _ -> 3600000
    end,

    inets:start(),
    {ok, #config{
        ollama_url = CleanStr(URLRaw),
        model      = CleanStr(ModelRaw),
        timeout    = Timeout
    }}.

handle_call({ollama, Prompt}, _From, Config) ->
    Result = call_ollama(Prompt, Config),
    {reply, Result, Config};

handle_call(_Request, _From, Config) ->
    {reply, {error, unknown_call}, Config}.

handle_cast(_Msg, Config) -> {noreply, Config}.
handle_info(_Msg, Config) -> {noreply, Config}.

%% --- Private Functions ---

call_ollama(Prompt, #config{ollama_url = URL, model = Model, timeout = T}) ->
    io:format("Consigliere: Consulting brain (~s) at ~s~n", [Model, URL]),
    
    %% SRE Fix: Give the model 2048 tokens and a stern System Prompt 
    %% to stop it from getting stuck in a reasoning loop.
    Payload = jsx:encode(#{
        <<"model">>  => iolist_to_binary(Model),
        <<"prompt">> => iolist_to_binary(Prompt),
        <<"stream">> => false,
        <<"system">> => <<"You are a helpful assistant. Output the answer immediately. Do not overthink.">>,
        <<"options">> => #{
            <<"num_predict">> => 2048, %% Enough room for yapping + joke
            <<"temperature">> => 0.8
        }
    }),
    
    case httpc:request(post, {URL, [], "application/json", Payload}, [{timeout, T}], []) of
        {ok, {{_, 200, _}, _Headers, Body}} ->
            parse_response(Body);
        {ok, {{_, Status, _}, _, Body}} ->
            {error, io_lib:format("Ollama HTTP ~p: ~s", [Status, Body])};
        {error, Reason} ->
            handle_error(Reason)
    end.

parse_response(Body) ->
    try
        BinaryBody = iolist_to_binary(Body),
        Data = jsx:decode(BinaryBody, [return_maps]),
        
        %% Log the "yapping" for SRE debugging
        case maps:find(<<"thinking">>, Data) of
            {ok, Thinking} -> io:format("~nDEBUG Reasoning:~n~s~n", [Thinking]);
            error -> ok
        end,

        case maps:find(<<"response">>, Data) of
            {ok, <<>>} -> 
                {ok, <<"Model exhausted tokens while thinking. Try a larger model.">>};
            {ok, BinaryResponse} -> 
                {ok, BinaryResponse};
            error -> 
                {error, <<"Malformed response">>}
        end
    catch
        _:_ -> {error, <<"Failed to decode Ollama JSON">>}
    end.

handle_error(Reason) ->
    io:format("Consigliere Network Error: ~p~n", [Reason]),
    {error, Reason}.
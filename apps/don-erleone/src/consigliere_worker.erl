-module(consigliere_worker).
-behaviour(gen_server).
-behaviour(poolboy_worker).
-include("records.hrl").

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link(Config) ->
    gen_server:start_link(?MODULE, Config, []).

init([Config]) -> {ok, Config}.

handle_call({consult, SessionId, Prompt, From}, _From, Config) ->
    PrevContext = mission_store:get_latest_context(SessionId),

    Result = case call_ollama(Prompt, PrevContext, Config) of
        {ok, OllamaData} ->
            process_and_route(SessionId, OllamaData, Prompt);
        Err ->
            Err
    end,

    %% FIX: Manual reply to the Cowboy process
    {ToPid, Tag} = From,
    ToPid ! {Tag, Result},

    %% FIX: Tell the pool manager the worker call itself is successful
    {reply, ok, Config}.

%% --- Internal Logic (Moved from consigliere.erl) ---

process_and_route(SessionId, OllamaData, Prompt) ->
    RawOptions = [
        maps:get(<<"response">>, OllamaData, <<>>),
        maps:get(<<"thinking">>, OllamaData, <<>>),
        maps:get(<<"content">>, OllamaData, <<>>)
    ],

    ActualData = find_json_payload(RawOptions),
    Response = maps:get(<<"response">>, ActualData, <<"Acknowledged.">>),
    IsDelegated = maps:get(<<"delegate_required">>, ActualData, false),
    NewContext = maps:get(<<"context">>, OllamaData, []),

    %% Final routing to Mission Store and Underboss
    route_mission(SessionId, IsDelegated, ActualData, NewContext, Response, Prompt).

route_mission(SessionId, true, Data, NewContext, Response, Prompt) ->
    Intent = maps:get(<<"tool_intent">>, Data, <<"unknown">>),
    {ok, Id} = mission_store:post_mission(SessionId, Intent, Prompt, NewContext),

    io:format("DEBUG: Worker ~p delegated Mission ~p for Session ~s~n", [self(), Id, SessionId]),

    Args = maps:get(<<"mcp_args">>, Data, #{}),
    underboss:recruit_sub_agent(#{id => Id, session_id => SessionId, intent => Intent, args => Args}),
    {ok, Response, #{mission_id => Id}};
route_mission(SessionId, false, _Data, NewContext, Response, Prompt) ->
    {ok, Id} = mission_store:post_mission(SessionId, <<"none">>, Prompt, NewContext),
    {ok, Response, #{mission_id => Id}}.

find_json_payload([]) ->
    #{};
find_json_payload([<<>> | T]) ->
    find_json_payload(T);
find_json_payload([Bin | T]) ->
    try
        jsx:decode(Bin, [return_maps])
    catch
        _:_ -> find_json_payload(T)
    end.

call_ollama(Prompt, PrevContext, #config{
    model = M, stream = S, systemPrompt = SP, ollama_url = URL, timeout = T
}) ->
    Payload = jsx:encode(#{
        <<"model">> => iolist_to_binary(M),
        <<"prompt">> => iolist_to_binary(Prompt),
        <<"context">> => PrevContext,
        <<"system">> => SP,
        <<"format">> => <<"json">>,
        <<"stream">> => S
    }),
    case httpc:request(post, {URL, [], "application/json", Payload}, [{timeout, T}], []) of
        {ok, {{_, 200, _}, _, Body}} -> {ok, jsx:decode(iolist_to_binary(Body), [return_maps])};
        {error, R} -> {error, R};
        {ok, {{_, Status, _}, _, _}} -> {error, {http, Status}}
    end.

%% Standard GenServer stubs
handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Msg, State) -> {noreply, State}.

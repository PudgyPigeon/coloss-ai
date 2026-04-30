-module(consigliere_worker).
-behaviour(gen_server).
-behaviour(poolboy_worker).
-include("records.hrl").

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% --- Lifecycle ---
start_link([Config]) -> gen_server:start_link(?MODULE, Config, []).
init(Config) -> {ok, Config}.

%% --- Orchestration ---
handle_call({consult, SessionId, Prompt, CowboyFrom}, _From, Config) ->
    try 
        %% Side Effect: Read from DB
        Context = mission_store:get_latest_context(SessionId),
        
        %% Side Effect: Network I/O
        case call_ollama(Prompt, Context, Config) of
            {ok, Data} ->
                Raw = extract_raw(Data),
                process_decision(SessionId, Prompt, Raw, Context, CowboyFrom);
            {error, R} -> 
                notify_error(CowboyFrom, R),
                {reply, {error, R}, Config}
        end
    catch
        _:E -> 
            notify_error(CowboyFrom, worker_fault),
            {reply, {error, E}, Config}
    end.

%% --- Side-Effect Handlers ---

process_decision(Sid, Prompt, Raw, PrevCtx, From) ->
    %% Call the Pure Logic
    Decision = mission_brain:analyze_llm_response(Raw, PrevCtx),
    NewCtx = mission_brain:build_new_context(Prompt, Raw, PrevCtx),

    case Decision of
        {delegate, Intent, Args, Msg} ->
            {ok, Mid} = mission_store:post_mission(Sid, Intent, Prompt, NewCtx),
            safe_send(From, {chunk, <<"\n", Msg/binary, "\n">>, Mid}),
            underboss:dispatch_mission(#{id => Mid, intent => Intent, args => Args, prompt => Prompt, cowboy_from => From}),
            {reply, ok, []};

        {direct, Msg} ->
            {ok, Mid} = mission_store:post_mission(Sid, <<"direct">>, Prompt, NewCtx),
            safe_send(From, {done, Msg, Mid}),
            {reply, ok, []}
    end.

%% --- Infrastructure Helpers ---

call_ollama(P, Ctx, #config{model=M, stream=S, system_prompt=SP, ollama_url=URL, timeout=T}) ->
    ollama_client:generate(P, SP, Ctx, #{url => URL, model => M, timeout => T, stream => S}).

safe_send({Pid, Tag}, Msg) -> 
    case is_process_alive(Pid) of
        true  -> Pid ! {Tag, Msg};
        false -> logger:warning("Target Cowboy PID ~p dead, dropped message.", [Pid])
    end.

notify_error({Pid, Tag}, R) -> 
    case is_process_alive(Pid) of
        true  -> Pid ! {Tag, {error, R}};
        false -> ok
    end.

extract_raw(#{<<"content">> := C}) -> C;
extract_raw(C) when is_binary(C) -> C;
extract_raw(_) -> <<"error">>.

handle_cast(_, S) -> {noreply, S}.
handle_info(_, S) -> {noreply, S}.
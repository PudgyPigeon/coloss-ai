%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_consigliere_worker).
-behaviour(gen_server).
-behaviour(poolboy_worker).
-include("records.hrl").

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% --- Lifecycle ---
start_link([Config]) -> gen_server:start_link(?MODULE, Config, []).
init(Config) -> {ok, Config}.

%% --- Orchestration ---
handle_call({consult, SessionId, Prompt, CowboyFrom}, _From, Config) ->
    logger:debug(#{event => worker_consult_start, session_id => SessionId}),
    try 
        %% Side Effect: Read from DB
        Context = de_store:get_latest_context(SessionId),
        
        %% Side Effect: Network I/O
        case call_ollama(Prompt, Context, Config) of
            {ok, Data} ->
                Raw = extract_raw(Data),
                %% SRE FIX: Pass Config into the decision router
                process_decision(SessionId, Prompt, Raw, Context, CowboyFrom, Config);
            {error, R} -> 
                logger:error(#{event => ollama_call_failed, session_id => SessionId, error => R}),
                notify_error(CowboyFrom, R),
                {reply, {error, R}, Config}
        end
    catch
        _:E:Stack -> 
            logger:error(#{event => worker_crash, session_id => SessionId, error => E, stack => Stack}),
            notify_error(CowboyFrom, worker_fault),
            {reply, {error, E}, Config}
    end.

%% --- Side-Effect Handlers ---

%% SRE FIX: Added Config as the 6th argument
process_decision(Sid, Prompt, Raw, PrevCtx, From, Config) ->
    %% Call the Pure Logic
    Decision = de_mission_brain:analyze_llm_response(Raw, PrevCtx),
    NewCtx = de_mission_brain:build_new_context(Prompt, Raw, PrevCtx),

    case Decision of
        {delegate, Intent, Args, Msg} ->
            logger:info(#{event => decision_delegate, session_id => Sid, intent => Intent}),
            case de_store:post_mission(Sid, Intent, Prompt, NewCtx) of
                {ok, Mid} ->
                    safe_send(From, {chunk, <<"\n", Msg/binary, "\n">>, Mid}),
                    de_underboss:dispatch_mission(#{id => Mid, intent => Intent, args => Args, prompt => Prompt, cowboy_from => From}),
                    %% SRE FIX: Return the intact Config instead of []
                    {reply, ok, Config};
                {error, Reason} ->
                    logger:error(#{event => de_store_failed, session_id => Sid, error => Reason}),
                    notify_error(From, Reason),
                    %% SRE FIX: Return the intact Config instead of []
                    {reply, {error, Reason}, Config}
            end;

        {direct, Msg} ->
            logger:info(#{event => decision_direct, session_id => Sid}),
            case de_store:post_mission(Sid, <<"direct">>, Prompt, NewCtx) of
                {ok, Mid} ->
                    safe_send(From, {done, Msg, Mid}),
                    %% SRE FIX: Return the intact Config instead of []
                    {reply, ok, Config};
                {error, Reason} ->
                    logger:error(#{event => de_store_failed, session_id => Sid, error => Reason}),
                    notify_error(From, Reason),
                    %% SRE FIX: Return the intact Config instead of []
                    {reply, {error, Reason}, Config}
            end
    end.

%% --- Infrastructure Helpers ---

call_ollama(P, Ctx, #config{model=M, stream=S, system_prompt=SP, ollama_url=URL, timeout=T}) ->
    de_ollama_client:generate(P, SP, Ctx, #{url => URL, model => M, timeout => T, stream => S}).

safe_send({Pid, Tag}, Msg) -> 
    case is_process_alive(Pid) of
        true  -> Pid ! {Tag, Msg};
        false -> logger:warning(#{event => cowboy_dead_drop, target_pid => Pid, message => Msg})
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
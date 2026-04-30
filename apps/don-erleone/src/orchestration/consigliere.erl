-module(consigliere).
-export([handle_mission/3]).

-ifdef(TEST).
-compile(export_all).
-endif.

%% ------------------------------------------------------------------------
%% API: The Dispatcher (Imperative Shell)
%% ------------------------------------------------------------------------

%% CowboyFrom = {Pid, Tag} — the cowboy handler blocks on receive for this Tag.
handle_mission(SessionId, Prompt, CowboyFrom) ->
    %% We use proc_lib:spawn to ensure the process is integrated into OTP error logging
    proc_lib:spawn(fun() -> async_pool_consult(SessionId, Prompt, CowboyFrom) end),
    ok.

%% ------------------------------------------------------------------------
%% Internal Helpers: Orchestration & Error Handling
%% ------------------------------------------------------------------------

async_pool_consult(SessionId, Prompt, CowboyFrom) ->
    try
        %% The Transaction: Request a worker from the pool
        poolboy:transaction(consigliere_pool, fun(Worker) ->
            %% infinity is used because Ollama generation can take 60s+
            %% and we want the pool queue to manage the pressure.
            gen_server:call(Worker, {consult, SessionId, Prompt, CowboyFrom}, infinity)
        end)
    catch
        %% Handle Pool Overload (e.g., if poolboy:transaction times out waiting for a worker)
        exit:{timeout, _} ->
            notify_client_of_failure(CowboyFrom, pool_overloaded);
        
        %% Handle Logic/Network crashes
        Class:Error:Stack ->
            logger:error("Consigliere dispatch failed: ~p:~p~nStack: ~p", [Class, Error, Stack]),
            notify_client_of_failure(CowboyFrom, internal_service_error)
    end.

%% ------------------------------------------------------------------------
%% Client Notification (Ensures Cowboy never hangs)
%% ------------------------------------------------------------------------

notify_client_of_failure({Pid, Tag}, Reason) ->
    %% Only send if the Cowboy process is still alive to receive it
    case is_process_alive(Pid) of
        true -> 
            Pid ! {Tag, {error, Reason}};
        false -> 
            logger:warning("Cowboy handler dead. Could not deliver error: ~p", [Reason])
    end.
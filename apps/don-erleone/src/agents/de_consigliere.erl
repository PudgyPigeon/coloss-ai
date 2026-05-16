%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_consigliere).
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
    StartTime = erlang:system_time(microsecond),
    telemetry:execute([don_erleone, worker, execute, start], #{time => StartTime}, #{session_id => SessionId, pool => de_consigliere_pool}),
    try
        %% The Transaction: Request a worker from the pool
        Result = poolboy:transaction(de_consigliere_pool, fun(Worker) ->
            %% infinity is used because Ollama generation can take 60s+
            %% and we want the pool queue to manage the pressure.
            gen_server:call(Worker, {consult, SessionId, Prompt, CowboyFrom}, infinity)
        end),
        telemetry:execute([don_erleone, worker, execute, stop], #{duration => erlang:system_time(microsecond) - StartTime}, #{session_id => SessionId, pool => de_consigliere_pool}),
        Result
    catch
        %% Handle Pool Overload (e.g., if poolboy:transaction times out waiting for a worker)
        exit:{timeout, _} ->
            telemetry:execute([don_erleone, worker, execute, exception], #{duration => erlang:system_time(microsecond) - StartTime}, #{session_id => SessionId, reason => pool_timeout}),
            notify_client_of_failure(CowboyFrom, pool_overloaded);
        
        %% Handle Logic/Network crashes
        Class:Error:Stack ->
            telemetry:execute([don_erleone, worker, execute, exception], #{duration => erlang:system_time(microsecond) - StartTime}, #{session_id => SessionId, class => Class, reason => Error}),
            logger:error(#{
                event => de_consigliere_dispatch_failed,
                session_id => SessionId,
                class => Class,
                error => Error,
                stack => Stack
            }),
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
            logger:warning(#{
                event => callback_delivery_failed,
                reason => Reason,
                target_pid => Pid
            })
    end.
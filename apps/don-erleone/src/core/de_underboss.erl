%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_underboss).
-include("records.hrl").
-behaviour(supervisor).

-export([start_link/1, dispatch_mission/1, init/1]).

%% ------------------------------------------------------------------------
%% API: Fleet Management
%% ------------------------------------------------------------------------

start_link(SubConfig) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, SubConfig).

dispatch_mission(MissionSpec) ->
    proc_lib:spawn(fun() -> async_transaction(MissionSpec) end),
    ok.

%% ------------------------------------------------------------------------
%% Supervisor Callbacks
%% ------------------------------------------------------------------------

init(SubConfig) ->
    logger:info(#{event => supervisor_init, module => ?MODULE}),
    SupFlags = #{
        strategy  => one_for_one,
        intensity => 10,
        period    => 60
    },
    
    ChildSpecs = [
        poolboy:child_spec(de_caporegime_pool, pool_config(), [SubConfig])
    ],
    
    {ok, {SupFlags, ChildSpecs}}.

%% ------------------------------------------------------------------------
%% Transaction Logic
%% ------------------------------------------------------------------------

async_transaction(MissionSpec) ->
    MissionId = maps:get(id, MissionSpec),
    StartTime = erlang:system_time(microsecond),
    telemetry:execute([don_erleone, worker, execute, start], #{time => StartTime}, #{mission_id => MissionId, pool => de_caporegime_pool}),
    try
        Result = poolboy:transaction(de_caporegime_pool, fun(Worker) ->
            %% SRE FIX: Changed 'infinity' to 300,000ms (5 minutes). 
            %% If the LLM or Haskell MCP completely hangs, we recover the worker slot.
            gen_server:call(Worker, {execute_mission, MissionSpec}, 300000)
        end),
        telemetry:execute([don_erleone, worker, execute, stop], #{duration => erlang:system_time(microsecond) - StartTime}, #{mission_id => MissionId, pool => de_caporegime_pool}),
        Result
    catch
        exit:{timeout, _} ->
            telemetry:execute([don_erleone, worker, execute, exception], #{duration => erlang:system_time(microsecond) - StartTime}, #{mission_id => MissionId, reason => pool_timeout}),
            handle_error(MissionSpec, exit, pool_exhausted_or_hung, []);
        Class:Reason:Stack ->
            telemetry:execute([don_erleone, worker, execute, exception], #{duration => erlang:system_time(microsecond) - StartTime}, #{mission_id => MissionId, class => Class, reason => Reason}),
            handle_error(MissionSpec, Class, Reason, Stack)
    end.

%% ------------------------------------------------------------------------
%% Internal Helpers & Error Boundary
%% ------------------------------------------------------------------------

pool_config() ->
    [
        {name, {local, de_caporegime_pool}},
        {worker_module, de_caporegime},
        {size, 3},
        {max_overflow, 10},
        {strategy, fifo}
    ].

handle_error(MissionSpec, Class, Reason, Stack) ->
    MissionId = maps:get(id, MissionSpec),
    logger:error(#{
        event => mission_failed,
        mission_id => MissionId,
        class => Class,
        reason => Reason,
        stack => Stack
    }),
    
    de_store:fail_mission(MissionId, {execution_error, Reason}),
    notify_caller(MissionSpec, Reason).

notify_caller(#{cowboy_from := {Pid, Tag}}, Reason) ->
    case is_process_alive(Pid) of
        true -> Pid ! {Tag, {error, {execution_failed, Reason}}};
        false -> ok
    end;
notify_caller(_, _) -> 
    ok.
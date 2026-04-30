-module(underboss).
-include("records.hrl").
-behaviour(supervisor).

-export([start_link/1, dispatch_mission/1, init/1]).

%% ------------------------------------------------------------------------
%% API
%% ------------------------------------------------------------------------

start_link(SubConfig) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, SubConfig).

%% Dispatches a mission asynchronously to avoid blocking the Consigliere.
dispatch_mission(MissionSpec) ->
    proc_lib:spawn(fun() -> async_transaction(MissionSpec) end),
    ok.

%% ------------------------------------------------------------------------
%% Supervisor Callbacks
%% ------------------------------------------------------------------------

init(SubConfig) ->
    SupFlags = #{
        strategy  => one_for_one,
        intensity => 5,
        period    => 10
    },
    
    %% Define the Caporegime worker pool
    ChildSpecs = [
        poolboy:child_spec(caporegime_pool, pool_config(), [SubConfig])
    ],
    
    {ok, {SupFlags, ChildSpecs}}.

%% ------------------------------------------------------------------------
%% Mission Dispatch Logic (The Transaction)
%% ------------------------------------------------------------------------

async_transaction(MissionSpec) ->
    try
        poolboy:transaction(caporegime_pool, fun(Worker) ->
            gen_server:call(Worker, {execute_mission, MissionSpec}, infinity)
        end)
    catch
        Class:Reason:Stack ->
            handle_error(MissionSpec, Class, Reason, Stack)
    end.

%% ------------------------------------------------------------------------
%% Internal Helpers
%% ------------------------------------------------------------------------

pool_config() ->
    [
        {name, {local, caporegime_pool}},
        {worker_module, caporegime},
        {size, 3},
        {max_overflow, 5}
    ].

handle_error(MissionSpec, Class, Reason, Stack) ->
    MissionId = maps:get(id, MissionSpec),
    
    %% 1. Log the failure
    logger:error("Dispatch failed for mission ~p: ~p:~p~n~p", 
                 [MissionId, Class, Reason, Stack]),
    
    %% 2. Update persistent state
    mission_store:fail_mission(MissionId, {dispatch_failed, Reason}),
    
    %% 3. Break the silence for the caller
    notify_caller_of_failure(MissionSpec, Reason).

notify_caller_of_failure(#{cowboy_from := {Pid, Tag}}, Reason) ->
    Pid ! {Tag, {execution_complete, {error, {dispatch_failed, Reason}}}};
notify_caller_of_failure(_, _) -> 
    ok.
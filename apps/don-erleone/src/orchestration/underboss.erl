-module(underboss).
-include("records.hrl").
-behaviour(supervisor).

-export([start_link/1, dispatch_mission/1, init/1]).

%% ------------------------------------------------------------------------
%% API: Fleet Management (Imperative Shell)
%% ------------------------------------------------------------------------

start_link(SubConfig) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, SubConfig).

%% Dispatches a mission asynchronously. 
%% Spawning here prevents the Consigliere pool from blocking while waiting for a Caporegime slot.
dispatch_mission(MissionSpec) ->
    proc_lib:spawn(fun() -> async_transaction(MissionSpec) end),
    ok.

%% ------------------------------------------------------------------------
%% Supervisor Callbacks
%% ------------------------------------------------------------------------

init(SubConfig) ->
    %% strategy: one_for_one — if the pool manager dies, it restarts independently.
    SupFlags = #{
        strategy  => one_for_one,
        intensity => 10,
        period    => 60
    },
    
    ChildSpecs = [
        poolboy:child_spec(caporegime_pool, pool_config(), [SubConfig])
    ],
    
    {ok, {SupFlags, ChildSpecs}}.

%% ------------------------------------------------------------------------
%% Transaction Logic: The Execution Shell
%% ------------------------------------------------------------------------

async_transaction(MissionSpec) ->
    try
        %% We use a transaction to lease a Caporegime worker.
        poolboy:transaction(caporegime_pool, fun(Worker) ->
            %% infinity because SRE autonomous loops can take several minutes.
            gen_server:call(Worker, {execute_mission, MissionSpec}, infinity)
        end)
    catch
        exit:{timeout, _} ->
            handle_error(MissionSpec, exit, pool_exhausted, []);
        Class:Reason:Stack ->
            handle_error(MissionSpec, Class, Reason, Stack)
    end.

%% ------------------------------------------------------------------------
%% Internal Helpers & Error Boundary
%% ------------------------------------------------------------------------

pool_config() ->
    [
        {name, {local, caporegime_pool}},
        {worker_module, caporegime},
        {size, 3},           %% Dedicated execution slots
        {max_overflow, 10},  %% Allow burst during heavy cluster incidents
        {strategy, fifo}
    ].

handle_error(MissionSpec, Class, Reason, Stack) ->
    MissionId = maps:get(id, MissionSpec),
    
    logger:error("Underboss: Mission ~p execution failed (~p:~p)~nStack: ~p", 
                 [MissionId, Class, Reason, Stack]),
    
    %% Sync the failure to Mnesia
    mission_store:fail_mission(MissionId, {execution_error, Reason}),
    
    %% Notify the Cowboy process so the UI shows the failure
    notify_caller(MissionSpec, Reason).

notify_caller(#{cowboy_from := {Pid, Tag}}, Reason) ->
    case is_process_alive(Pid) of
        true -> 
            %% We use the same message format the Caporegime would use for consistency
            Pid ! {Tag, {error, {execution_failed, Reason}}};
        false -> 
            ok
    end;
notify_caller(_, _) -> 
    ok.
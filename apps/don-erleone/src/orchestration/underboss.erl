-module(underboss).
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
%% Transaction Logic
%% ------------------------------------------------------------------------

async_transaction(MissionSpec) ->
    try
        poolboy:transaction(caporegime_pool, fun(Worker) ->
            %% SRE FIX: Changed 'infinity' to 300,000ms (5 minutes). 
            %% If the LLM or Haskell MCP completely hangs, we recover the worker slot.
            gen_server:call(Worker, {execute_mission, MissionSpec}, 300000)
        end)
    catch
        exit:{timeout, _} ->
            handle_error(MissionSpec, exit, pool_exhausted_or_hung, []);
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
        {size, 3},
        {max_overflow, 10},
        {strategy, fifo}
    ].

handle_error(MissionSpec, Class, Reason, Stack) ->
    MissionId = maps:get(id, MissionSpec),
    logger:error("Underboss: Mission ~p execution failed (~p:~p)~nStack: ~p", 
                 [MissionId, Class, Reason, Stack]),
    
    mission_store:fail_mission(MissionId, {execution_error, Reason}),
    notify_caller(MissionSpec, Reason).

notify_caller(#{cowboy_from := {Pid, Tag}}, Reason) ->
    case is_process_alive(Pid) of
        true -> Pid ! {Tag, {error, {execution_failed, Reason}}};
        false -> ok
    end;
notify_caller(_, _) -> 
    ok.
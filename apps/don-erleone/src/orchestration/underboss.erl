-module(underboss).
-include("records.hrl").
-behaviour(supervisor).

-export([start_link/1, dispatch_mission/1, init/1]).

-ifdef(TEST).
-compile(export_all).
-endif.

start_link(SubConfig) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, SubConfig).

%% Called by consigliere_worker when delegation is required.
%% Grabs a caporegime from the pool and dispatches the mission async.
dispatch_mission(MissionSpec) ->
    proc_lib:spawn(fun() -> do_dispatch(MissionSpec) end),
    ok.

init(SubConfig) ->
    PoolArgs = [
        {name, {local, caporegime_pool}},
        {worker_module, caporegime},
        {size, 3},
        {max_overflow, 5}
    ],

    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },

    ChildSpecs = [
        poolboy:child_spec(caporegime_pool, PoolArgs, [SubConfig])
    ],
    {ok, {SupFlags, ChildSpecs}}.

%% --- Internal Helpers ---

do_dispatch(MissionSpec) ->
    try
        poolboy:transaction(caporegime_pool, fun(Worker) ->
            gen_server:call(Worker, {execute_mission, MissionSpec}, infinity)
        end)
    catch
        Class:Reason:Stack ->
            handle_dispatch_error(MissionSpec, Class, Reason, Stack)
    end.

handle_dispatch_error(MissionSpec, Class, Reason, Stack) ->
    Id = maps:get(id, MissionSpec),
    logger:error(
        "Underboss failed to dispatch mission ~p. ~p:~p~n~p",
        [Id, Class, Reason, Stack]
    ),
    mission_store:fail_mission(Id, {dispatch_failed, Reason}),
    %% Notify the cowboy handler so the SSE stream doesn't hang
    case maps:get(cowboy_from, MissionSpec, undefined) of
        {CowboyPid, CowboyTag} ->
            CowboyPid ! {CowboyTag, {execution_complete, {error, {dispatch_failed, Reason}}}};
        _ ->
            ok
    end.

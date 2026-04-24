-module(underboss_tests).
-include_lib("eunit/include/eunit.hrl").

dispatch_mission_test_() ->
    {setup,
     fun() ->
         %% Intercept poolboy and mission_store to test full failure recovery
         meck:new(poolboy, [non_strict]),
         meck:new(mission_store, [non_strict]),
         %% Intercept and silence the expected error logs
         meck:new(logger, [unstick, passthrough]),
         meck:expect(logger, error, fun(_Format, _Args) -> ok end),
         ok
     end,
     fun(_) ->
         meck:unload(logger),
         meck:unload(poolboy),
         meck:unload(mission_store)
     end,
     fun() ->
         TestPid = self(),
         
         %% 1. Force the poolboy transaction to crash violently
         meck:expect(poolboy, transaction, fun(_Pool, _Fun) ->
             erlang:error(simulated_pool_exhaustion)
         end),
         
         %% 2. Expect that handle_dispatch_error caught it and updated the DB
         meck:expect(mission_store, fail_mission, fun(Id, Reason) ->
             TestPid ! {mission_failed, Id, Reason},
             ok
         end),
         
         MissionSpec = #{id => 999, intent => <<"test">>},
         ?assertEqual(ok, underboss:dispatch_mission(MissionSpec)),
         
         %% 3. Assert the DB update was triggered with the correct failure reason
         receive 
             {mission_failed, 999, {dispatch_failed, simulated_pool_exhaustion}} -> ok
         after 1000 -> 
             erlang:error(timeout_waiting_for_fail_mission)
         end
     end}.
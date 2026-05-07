-module(de_underboss_tests).
-include_lib("eunit/include/eunit.hrl").

dispatch_mission_test_() ->
    {setup,
        fun() ->
            %% Intercept poolboy and de_store to test full failure recovery
            meck:new(poolboy, [non_strict]),
            meck:new(de_store, [non_strict]),
            %% Intercept and silence the expected error logs
            meck:new(logger, [unstick, passthrough]),
            meck:expect(logger, error, fun(_Format, _Args) -> ok end),
            ok
        end,
        fun(_) ->
            meck:unload(logger),
            meck:unload(poolboy),
            meck:unload(de_store)
        end,
        fun() ->
            TestPid = self(),
            Tag = make_ref(),
            CowboyFrom = {TestPid, Tag},

            %% 1. Force the poolboy transaction to crash violently
            meck:expect(poolboy, transaction, fun(_Pool, _Fun) ->
                erlang:error(simulated_pool_exhaustion)
            end),

            %% 2. Expect that handle_dispatch_error caught it and updated the DB
            meck:expect(de_store, fail_mission, fun(Id, Reason) ->
                TestPid ! {mission_failed, Id, Reason},
                ok
            end),

            MissionSpec = #{id => 999, intent => <<"test">>, cowboy_from => CowboyFrom},
            ?assertEqual(ok, de_underboss:dispatch_mission(MissionSpec)),

            %% 3. Assert the DB update was triggered with the correct failure reason
            receive
                {mission_failed, 999, {execution_error, simulated_pool_exhaustion}} -> ok
            after 1000 ->
                erlang:error(timeout_waiting_for_fail_mission)
            end,

            %% 4. Assert the cowboy handler was also notified of the failure
            receive
                {Tag, {error, {execution_failed, simulated_pool_exhaustion}}} ->
                    ok
            after 1000 ->
                erlang:error(timeout_waiting_for_cowboy_notification)
            end
        end}.

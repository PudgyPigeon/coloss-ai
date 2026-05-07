-module(de_store_tests).
-include_lib("eunit/include/eunit.hrl").
-include("../include/records.hrl").

de_store_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        fun test_post_and_get/0,
        fun test_update_status/0,
        fun test_complete_and_fail/0,
        fun test_get_latest_context/0,
        fun test_get_pending_missions/0
    ]}.

setup() ->
    %% Use a custom directory for tests so we don't mess up local dev data
    application:set_env(mnesia, dir, ".mnesia_test_dir"),
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    mnesia:start(),
    de_store:init_db(),
    ok.

cleanup(_) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

test_post_and_get() ->
    {ok, Id} = de_store:post_mission(<<"sess1">>, <<"intent1">>, <<"prompt">>, [1, 2, 3]),
    {ok, Mission} = de_store:get_mission(Id),
    ?assertEqual(Id, Mission#mission.id),
    ?assertEqual(<<"sess1">>, Mission#mission.session_id),
    ?assertEqual(<<"intent1">>, Mission#mission.intent),
    ?assertEqual(pending, Mission#mission.status).

test_update_status() ->
    {ok, Id} = de_store:post_mission(<<"sess2">>, <<"intent2">>, <<"prompt">>, []),
    ok = de_store:update_status(Id, in_progress),
    {ok, Mission} = de_store:get_mission(Id),
    ?assertEqual(in_progress, Mission#mission.status).

test_complete_and_fail() ->
    {ok, Id1} = de_store:post_mission(<<"sess3">>, <<"intent">>, <<"p">>, []),
    ok = de_store:complete_mission(Id1, <<"success">>),
    {ok, M1} = de_store:get_mission(Id1),
    ?assertEqual(completed, M1#mission.status),
    ?assertEqual(<<"success">>, M1#mission.result),

    {ok, Id2} = de_store:post_mission(<<"sess3">>, <<"intent">>, <<"p">>, []),
    ok = de_store:fail_mission(Id2, <<"error">>),
    {ok, M2} = de_store:get_mission(Id2),
    ?assertEqual(failed, M2#mission.status),
    ?assertEqual(<<"error">>, M2#mission.error).

test_get_latest_context() ->
    de_store:post_mission(<<"ctx_sess">>, <<"i">>, <<"p">>, [1]),
    %% Ensure timestamp difference
    timer:sleep(10),
    de_store:post_mission(<<"ctx_sess">>, <<"i">>, <<"p">>, [1, 2]),
    Context = de_store:get_latest_context(<<"ctx_sess">>),
    ?assertEqual([1, 2], Context),
    ?assertEqual([], de_store:get_latest_context(<<"unknown">>)).

test_get_pending_missions() ->
    {ok, Id} = de_store:post_mission(<<"pend_sess">>, <<"i">>, <<"p">>, []),
    {ok, Pending} = de_store:get_pending_missions(),
    Ids = [M#mission.id || M <- Pending],
    ?assert(lists:member(Id, Ids)).

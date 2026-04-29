-module(consigliere_worker_tests).
-include_lib("eunit/include/eunit.hrl").
-export([consigliere_test_/1]).

consigliere_test_(_) ->
    {setup,
     fun() -> mnesia:start() end,  %% Setup
     fun(_) -> mnesia:stop() end,   %% Teardown
     [
      fun extract_mission_data_test/0,
      fun extract_mission_data_fallback_test/0
     ]}.

find_json_payload_test() ->
    ?assertEqual(#{}, consigliere_worker:find_json_payload([])),
    ?assertEqual(#{}, consigliere_worker:find_json_payload([<<"not json">>, <<>>])),
    ValidJson = <<"{\"key\": \"value\"}">>,
    ?assertEqual(
        #{<<"key">> => <<"value">>},
        consigliere_worker:find_json_payload([<<"bad">>, ValidJson, <<"other">>])
    ).

extract_mission_data_test() ->
    OllamaRaw = <<"{\"delegate_required\": true, \"tool_intent\": \"k8s_deploy\", \"response\": \"Delegating\"}">>,
    {Data, Raw} = consigliere_worker:extract_mission_data(OllamaRaw),
    ?assertEqual(OllamaRaw, Raw),
    ?assert(maps:get(<<"delegate_required">>, Data)).

extract_mission_data_fallback_test() ->
    FakeOllama = <<"Just plain text here.">>,
    {Data, Raw} = consigliere_worker:extract_mission_data(FakeOllama),
    ?assertEqual(<<"Acknowledged.">>, maps:get(<<"response">>, Data)),
    ?assertEqual(FakeOllama, Raw).

build_mission_spec_test() ->
    CowboyFrom = {self(), make_ref()},
    Spec = consigliere_worker:build_mission_spec(
        1, <<"sess">>, <<"intent">>, #{}, <<"prompt">>, CowboyFrom
    ),
    ?assertEqual(1, maps:get(id, Spec)),
    ?assertEqual(<<"sess">>, maps:get(session_id, Spec)),
    ?assertEqual(CowboyFrom, maps:get(cowboy_from, Spec)).

-module(consigliere_worker_tests).
-include_lib("eunit/include/eunit.hrl").

find_json_payload_test() ->
    ?assertEqual(#{}, consigliere_worker:find_json_payload([])),
    ?assertEqual(#{}, consigliere_worker:find_json_payload([<<"not json">>, <<>>])),
    ValidJson = <<"{\"key\": \"value\"}">>,
    ?assertEqual(#{<<"key">> => <<"value">>}, consigliere_worker:find_json_payload([<<"bad">>, ValidJson, <<"other">>])).

extract_mission_data_test() ->
    OllamaData = #{
        <<"response">> => <<"{\"delegate_required\": true, \"tool_intent\": \"k8s_deploy\"}">>,
        <<"context">> => [1, 2, 3]
    },
    Data = consigliere_worker:extract_mission_data(OllamaData),
    ?assertEqual(true, maps:get(<<"delegate_required">>, Data)),
    ?assertEqual(<<"k8s_deploy">>, maps:get(<<"tool_intent">>, Data)),
    ?assertEqual([1, 2, 3], maps:get(<<"context">>, Data)).

extract_mission_data_fallback_test() ->
    %% Test that when Ollama returns invalid JSON or plain text, we fallback safely
    OllamaData = #{<<"response">> => <<"Just plain text here.">>},
    Data = consigliere_worker:extract_mission_data(OllamaData),
    ?assertEqual(false, maps:get(<<"delegate_required">>, Data)),
    ?assertEqual(<<"unknown">>, maps:get(<<"tool_intent">>, Data)),
    ?assertEqual(<<"Acknowledged.">>, maps:get(<<"response">>, Data)).

build_mission_spec_test() ->
    Spec = consigliere_worker:build_mission_spec(1, <<"sess">>, <<"intent">>, #{}, <<"prompt">>),
    ?assertEqual(1, maps:get(id, Spec)),
    ?assertEqual(<<"sess">>, maps:get(session_id, Spec)).
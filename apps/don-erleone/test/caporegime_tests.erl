-module(caporegime_tests).
-include_lib("eunit/include/eunit.hrl").

build_sub_prompt_test() ->
    K8sPrompt = caporegime:build_sub_prompt(<<"k8s_deploy">>, <<"Deploy nginx">>, #{}),
    ?assertMatch({_, _}, binary:match(K8sPrompt, <<"Kubernetes deployment">>)),

    McpPrompt = caporegime:build_sub_prompt(<<"check_mcp">>, <<"Status">>, #{}),
    ?assertMatch({_, _}, binary:match(McpPrompt, <<"infrastructure status">>)),

    OtherPrompt = caporegime:build_sub_prompt(<<"unknown">>, <<"Do this">>, #{}),
    ?assertMatch({_, _}, binary:match(OtherPrompt, <<"delegated task">>)).

build_mcp_payload_test() ->
    Args = #{<<"endpoint">> => <<"http://test">>, <<"foo">> => <<"bar">>},
    Payload = caporegime:build_mcp_payload(Args),
    Decoded = jsx:decode(Payload, [return_maps]),
    ?assertNot(maps:is_key(<<"endpoint">>, Decoded)),
    ?assertEqual(<<"bar">>, maps:get(<<"foo">>, Decoded)).
-module(caporegime_tests).
-include_lib("eunit/include/eunit.hrl").

build_sub_prompt_test_() ->
    Cases = [
        {<<"k8s_deploy">>, <<"Deploy nginx">>, <<"Kubernetes deployment">>},
        {<<"check_mcp">>, <<"Status">>, <<"infrastructure status">>},
        {<<"unknown">>, <<"Do this">>, <<"delegated task">>}
    ],
    [
        %% The test generator iterates through the list
        {
            lists:flatten(io_lib:format("Testing ~s prompt", [Task])),
            ?_assertMatch(
                {_, _},
                binary:match(
                    caporegime:build_sub_prompt(Task, Input, #{}),
                    ExpectedSubString
                )
            )
        }
     || {Task, Input, ExpectedSubString} <- Cases
    ].

build_mcp_payload_test() ->
    Args = #{<<"endpoint">> => <<"http://test">>, <<"foo">> => <<"bar">>},
    Payload = caporegime:build_mcp_payload(Args),
    Decoded = jsx:decode(Payload, [return_maps]),
    ?assertNot(maps:is_key(<<"endpoint">>, Decoded)),
    ?assertEqual(<<"bar">>, maps:get(<<"foo">>, Decoded)).

notify_caller_test() ->
    Tag = make_ref(),
    CowboyFrom = {self(), Tag},
    MissionSpec = #{id => 1, cowboy_from => CowboyFrom},
    Result = {ok, #{response => <<"done">>}},

    caporegime:notify_caller(MissionSpec, Result),

    receive
        {Tag, {chunk, _, _}} -> 
            receive
                {Tag, {done, _, _}} -> ok
            after 1000 -> erlang:error(timeout_on_done)
            end
    after 1000 ->
        erlang:error(timeout_waiting_for_notify_caller)
    end.

notify_caller_no_from_test() ->
    %% Should not crash when cowboy_from is absent (backward compat)
    MissionSpec = #{id => 2},
    ?assertEqual(ok, caporegime:notify_caller(MissionSpec, {ok, #{}})).

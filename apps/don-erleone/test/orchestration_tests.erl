-module(orchestration_tests). %% Standard naming: <module>_tests
-include_lib("eunit/include/eunit.hrl").

%% This is a "Live" Integration Test
%% It requires the app to be running (or started by the test)
delegation_integration_test() ->
    {ok, _} = application:ensure_all_started(don_erleone),
    
    %% Use Meck to prevent actual HTTP calls during EUnit
    meck:new(ollama_client),
    meck:expect(ollama_client, generate, 4, {ok, <<"{\"delegate_required\": false, \"response\": \"ok\"}">>}),
    
    Tag = make_ref(),
    consigliere:handle_mission(<<"test_session">>, <<"Hi">>, {self(), Tag}),
    
    Result = receive 
        {Tag, {done, _, _}} -> ok
    after 5000 -> timeout
    end,
    
    meck:unload(ollama_client),
    ?assertEqual(ok, Result).
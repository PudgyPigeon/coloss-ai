-module(ollama_client_tests).
-include_lib("eunit/include/eunit.hrl").

to_binary_test() ->
    ?assertEqual(<<"hello">>, ollama_client:to_binary(<<"hello">>)),
    ?assertEqual(<<"world">>, ollama_client:to_binary("world")),
    ?assertEqual(<<"123">>, ollama_client:to_binary(123)).

to_list_test() ->
    ?assertEqual("hello", ollama_client:to_list(<<"hello">>)),
    ?assertEqual("world", ollama_client:to_list("world")).

build_payload_test() ->
    Payload = ollama_client:build_payload("qwen", <<"Hello">>, [1, 2, 3], <<"System">>, false),
    Decoded = jsx:decode(Payload, [return_maps]),
    ?assertEqual(<<"qwen">>, maps:get(<<"model">>, Decoded)),
    ?assertEqual(<<"Hello">>, maps:get(<<"prompt">>, Decoded)),
    ?assertEqual([1, 2, 3], maps:get(<<"context">>, Decoded)),
    ?assertEqual(<<"System">>, maps:get(<<"system">>, Decoded)),
    ?assertEqual(false, maps:get(<<"stream">>, Decoded)).
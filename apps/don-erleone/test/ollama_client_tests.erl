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
    Messages = maps:get(<<"messages">>, Decoded),
    ExpectedMessages = [
        #{<<"role">> => <<"system">>, <<"content">> => <<"System">>},
        1,
        2,
        3,
        #{<<"role">> => <<"user">>, <<"content">> => <<"Hello">>}
    ],
    ?assertEqual(ExpectedMessages, Messages),
    ?assertEqual(false, maps:get(<<"stream">>, Decoded)).

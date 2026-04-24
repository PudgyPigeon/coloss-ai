-module(don_erleone_tests).
-include_lib("eunit/include/eunit.hrl").

get_env_string_test() ->
    application:set_env(don_erleone, test_str, "hello"),
    ?assertEqual("hello", don_erleone:get_env_string(test_str, "default")),
    application:set_env(don_erleone, test_bin, <<"world">>),
    ?assertEqual("world", don_erleone:get_env_string(test_bin, "default")),
    ?assertEqual("default", don_erleone:get_env_string(missing_key, "default")).

get_env_integer_test() ->
    application:set_env(don_erleone, test_int, 42),
    ?assertEqual(42, don_erleone:get_env_integer(test_int, 10)),
    application:set_env(don_erleone, test_int_str, "100"),
    ?assertEqual(100, don_erleone:get_env_integer(test_int_str, 10)),
    application:set_env(don_erleone, test_int_bin, <<"200">>),
    ?assertEqual(200, don_erleone:get_env_integer(test_int_bin, 10)),
    application:set_env(don_erleone, test_bad, "not_int"),
    ?assertEqual(10, don_erleone:get_env_integer(test_bad, 10)),
    ?assertEqual(10, don_erleone:get_env_integer(missing_key, 10)).

get_system_prompt_test() ->
    Prompt = don_erleone:get_system_prompt(),
    ?assert(is_binary(Prompt)).
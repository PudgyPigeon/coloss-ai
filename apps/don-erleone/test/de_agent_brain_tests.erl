%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_agent_brain_tests).
-include_lib("eunit/include/eunit.hrl").

analyze_priority_tools_test() ->
  Msg = #{<<"content">> => <<"Hi">>, <<"tool_calls">> => [#{<<"id">> => 1}]},
  ?assertEqual({continue, [#{<<"id">> => 1}]}, de_agent_brain:analyze_loop_step(Msg)).

analyze_stop_content_test() ->
  Msg = #{<<"content">> => <<"Mission complete">>},
  ?assertEqual({stop, <<"Mission complete">>}, de_agent_brain:analyze_loop_step(Msg)).

analyze_fallback_stop_test() ->
  Msg = #{},
  ?assertEqual({stop, <<"Mission complete or no further action required.">>}, de_agent_brain:analyze_loop_step(Msg)).

decode_mcp_result_test() ->
  Body = <<"{\"result\": {\"tools\": [1, 2]}}">>,
  ?assertEqual({ok, [1, 2]}, de_agent_brain:decode_tools(Body)).

decode_flat_tools_test() ->
  Body = <<"{\"tools\": [3, 4]}">>,
  ?assertEqual({ok, [3, 4]}, de_agent_brain:decode_tools(Body)).

decode_invalid_json_test() ->
  ?assertEqual({error, json_invalid}, de_agent_brain:decode_tools(<<"{">>)).

decode_bad_structure_test() ->
  ?assertMatch({error, {bad_structure, _}}, de_agent_brain:decode_tools(<<"{}">>)).

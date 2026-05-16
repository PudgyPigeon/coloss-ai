%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_ollama_client_tests).
-include_lib("eunit/include/eunit.hrl").

-define(CTX, #{conn => self(), ref => ref, tmo => 1000, host => "host", is_stream => true, cb => undefined}).

%% Silence noisy logs during tests
logger_test_() ->
  {setup,
    fun() -> logger:set_primary_config(#{level => none}) end,
    fun(_) -> logger:set_primary_config(#{level => info}) end,
    [
      fun t_handle_200/0,
      fun t_handle_404/0,
      fun t_handle_gun_error_stream/0,
      fun t_handle_gun_error_general/0,
      fun t_handle_gun_down/0,
      fun t_parse_standard_url/0,
      fun t_parse_default_port_url/0
    ]
  }.

t_handle_200() ->
  Msg = {gun_response, self(), ref, nofin, 200, []},
  ?assertEqual({next, <<>>, <<>>},
               de_ollama_client:handle_stream_event(Msg, ?CTX, <<>>, <<>>)).

t_handle_404() ->
  Msg = {gun_response, self(), ref, nofin, 404, []},
  ?assertEqual({error, {http_status, 404}},
               de_ollama_client:handle_stream_event(Msg, ?CTX, <<>>, <<>>)).

t_handle_gun_error_stream() ->
  Msg = {gun_error, self(), ref, reason},
  ?assertEqual({error, {stream_err, reason}},
               de_ollama_client:handle_stream_event(Msg, ?CTX, <<>>, <<>>)).

t_handle_gun_error_general() ->
  Msg = {gun_error, self(), reason},
  ?assertEqual({error, {gun_err, reason}},
               de_ollama_client:handle_stream_event(Msg, ?CTX, <<>>, <<>>)).

t_handle_gun_down() ->
  Msg = {gun_down, self(), http, closed, [], []},
  ?assertEqual({error, connection_closed},
               de_ollama_client:handle_stream_event(Msg, ?CTX, <<>>, <<>>)).

t_parse_standard_url() ->
  ?assertEqual({"localhost", 11434, "/api/chat"},
               de_ollama_client:parse_endpoint("http://localhost:11434/api/chat")).

t_parse_default_port_url() ->
  ?assertEqual({"ollama", 80, "/api/chat"},
               de_ollama_client:parse_endpoint("http://ollama/api/chat")).

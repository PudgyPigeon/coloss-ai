%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_store_failures_tests).
-include_lib("eunit/include/eunit.hrl").

logger_test_() ->
  {setup,
    fun() -> logger:set_primary_config(#{level => none}) end,
    fun(_) -> logger:set_primary_config(#{level => info}) end,
    [
      fun t_handle_transaction_atomic/0,
      fun t_handle_transaction_aborted/0,
      fun t_handle_read_found/0,
      fun t_handle_read_not_found/0,
      fun t_handle_read_error/0,
      fun t_handle_write_success/0,
      fun t_handle_write_failure/0
    ]
  }.

t_handle_transaction_atomic() ->
  ?assertEqual(ok, de_store:handle_transaction({atomic, ok}, 1)).

t_handle_transaction_aborted() ->
  ?assertEqual({error, fail}, de_store:handle_transaction({aborted, fail}, 1)).

t_handle_read_found() ->
  ?assertEqual({ok, rec}, de_store:handle_read_result([rec])).

t_handle_read_not_found() ->
  ?assertEqual({error, not_found}, de_store:handle_read_result([])).

t_handle_read_error() ->
  ?assertEqual({error, fail}, de_store:handle_read_result({error, fail})).

t_handle_write_success() ->
  ?assertEqual({ok, 1}, de_store:handle_write_result(ok, 1)).

t_handle_write_failure() ->
  ?assertEqual({error, fail}, de_store:handle_write_result({error, fail}, 1)).

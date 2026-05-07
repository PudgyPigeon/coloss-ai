-module(de_utils).

-export([to_list/1, any_to_int/1]).

to_list(V) when is_binary(V) -> binary_to_list(V);
to_list(V) when is_list(V)   -> V;
to_list(V)                   -> lists:flatten(io_lib:format("~p", [V])).

any_to_int(V) when is_list(V)    -> list_to_integer(V);
any_to_int(V) when is_binary(V)  -> binary_to_integer(V);
any_to_int(V) when is_integer(V) -> V;
any_to_int(V) when is_atom(V)    -> any_to_int(atom_to_list(V)).

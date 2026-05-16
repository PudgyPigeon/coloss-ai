%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_ollama_brain).
-export([build_payload/6, parse_line/2]).

%% @doc Pure logic for constructing the Ollama request
build_payload(Model, Prompt, Context, System, Stream, Tools) ->
    Messages = [
        #{<<"role">> => <<"system">>, <<"content">> => to_bin(System)}
    ] ++ Context ++ [
        #{<<"role">> => <<"user">>,   <<"content">> => to_bin(Prompt)}
    ],
    
    Payload = #{
        <<"model">>    => to_bin(Model),
        <<"messages">> => Messages,
        <<"stream">>   => Stream
    },
    
    jsx:encode(maybe_add_tools(Payload, Tools)).

%% @doc Pure logic for handling a single line of NDJSON
parse_line(Line, Acc) ->
    try jsx:decode(Line, [return_maps]) of
        #{<<"message">> := #{<<"content">> := C}} -> 
            case is_binary(Acc) of
                true -> <<Acc/binary, C/binary>>;
                false -> C
            end;
        #{<<"message">> := Msg} -> Msg;
        _ -> Acc
    catch _:_ -> Acc end.

%% --- Private Helpers ---

maybe_add_tools(Payload, []) -> 
    Payload;
maybe_add_tools(Payload, Tools) -> 
    Payload#{<<"tools">> => Tools}.

to_bin(B) when is_binary(B) -> 
    B;
to_bin(L) when is_list(L) -> 
    list_to_binary(L);
to_bin(A) when is_atom(A) -> 
    atom_to_binary(A, utf8);
to_bin(Any) -> 
    iolist_to_binary(io_lib:format("~p", [Any])).
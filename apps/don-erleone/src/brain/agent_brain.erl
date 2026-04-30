-module(agent_brain).

%% Internal Protocol Constants
-define(MCP_VERSION, <<"2025-06-18">>).
-define(JSONRPC_VER, <<"2.0">>).

-export([
    analyze_loop_step/1, 
    decode_tools/1, 
    build_sub_prompt/3, 
    prepare_mcp_request/2
]).

%% =============================================================================
%% MCP Protocol Abstraction
%% =============================================================================

%% @doc Generates the headers required for the MCP HTTP transport.
mcp_headers() ->
    [
        {<<"Content-Type">>, <<"application/json">>},
        {<<"Accept">>, <<"application/json">>},
        {<<"Mcp-Protocol-Version">>, ?MCP_VERSION}
    ].

%% @doc Constructs the map for a JSON-RPC 2.0 request.
json_rpc_map(Method, Params, Id) ->
    #{
        <<"jsonrpc">> => ?JSONRPC_VER,
        <<"id">> => Id,
        <<"method">> => to_bin(Method),
        <<"params">> => if Params == undefined -> #{}; true -> Params end
    }.

%% @doc High-level logic: Returns {Headers, JSON_Payload} for the Shell (Caporegime).
prepare_mcp_request(Method, Params) ->
    Headers = mcp_headers(),
    %% We use a fixed ID 1 for simple request/response, Shell can extend if needed.
    PayloadMap = json_rpc_map(Method, Params, 1),
    {Headers, jsx:encode(PayloadMap)}.

%% =============================================================================
%% Agent Logic & Decoding
%% =============================================================================

%% @doc Pure logic to determine if we should call more tools or finish based on LLM response.
analyze_loop_step(OllamaMsg) ->
    case OllamaMsg of
        #{<<"tool_calls">> := Calls} when is_list(Calls) -> {continue, Calls};
        #{<<"content">> := C} -> {stop, C};
        _ -> {stop, <<"Malformed LLM response structure.">>}
    end.

%% @doc Decodes and validates the tools list returned by the Haskell MCP Underboss.
decode_tools(Body) ->
    try
        Decoded = jsx:decode(to_bin(Body), [return_maps]),
        case Decoded of
            #{<<"result">> := #{<<"tools">> := T}} -> {ok, T};
            #{<<"tools">> := T} -> {ok, T};
            _ -> 
                logger:error("MCP Result structure mismatch: ~p", [Decoded]),
                {error, structure_mismatch}
        end
    catch 
        _:_ -> {error, json_invalid}
    end.

%% @doc Prepares a sub-prompt for the autonomous agent loop.
build_sub_prompt(Intent, Goal, ArgsMap) ->
    ArgsJson = try jsx:encode(ArgsMap) catch _:_ -> <<"{ }">> end,
    << "Agent Intent: ", Intent/binary, 
       "\nGoal: ", Goal/binary, 
       "\nParams: ", ArgsJson/binary >>.

%% =============================================================================
%% Helpers
%% =============================================================================

%% @doc Ensures input is a binary.
to_bin(B) when is_binary(B) -> B;
to_bin(L) -> iolist_to_binary(io_lib:format("~s", [L])).
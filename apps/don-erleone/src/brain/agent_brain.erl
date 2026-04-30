-module(agent_brain).

-define(MCP_VERSION, <<"2025-06-18">>).
-define(JSONRPC_VER, <<"2.0">>).

-export([
    analyze_loop_step/1, 
    decode_tools/1, 
    build_sub_prompt/3, 
    prepare_mcp_request/2
]).

%% =============================================================================
%% MCP Protocol
%% =============================================================================

prepare_mcp_request(Method, Params) ->
    Headers = [
        {<<"Content-Type">>, <<"application/json">>},
        {<<"Mcp-Protocol-Version">>, ?MCP_VERSION} %% Ensure this is set
    ],
    
    %% Standard MCP tools/call structure
    Payload = #{
        <<"jsonrpc">> => ?JSONRPC_VER,
        <<"id">> => 1,
        <<"method">> => to_bin(Method),
        <<"params">> => Params
    },
    {Headers, jsx:encode(Payload)}.

%% =============================================================================
%% The "One-Stop" Logic
%% =============================================================================

analyze_loop_step(Msg) ->
    %% SRE Priority: If the model gave us an answer, STOP, even if it hallucinations a tool call.
    HasContent = maps:get(<<"content stream">>, Msg, maps:get(<<"content">>, Msg, <<>>)),
    HasTools = maps:get(<<"tool_calls">>, Msg, []),

    case {HasContent, HasTools} of
        {C, _} when is_binary(C), byte_size(C) > 20 -> 
            %% If we have substantial content, assume it's the answer.
            {stop, C};
        {_, Calls} when is_list(Calls), length(Calls) > 0 -> 
            {continue, Calls};
        {C, _} when is_binary(C), byte_size(C) > 0 -> 
            {stop, C};
        _ -> 
            {stop, <<"Mission complete or no further action required.">>}
    end.

decode_tools(Body) ->
    try
        Decoded = jsx:decode(to_bin(Body), [return_maps]),
        case Decoded of
            #{<<"result">> := #{<<"tools">> := T}} -> {ok, T};
            #{<<"tools">> := T} -> {ok, T};
            _ -> {error, {bad_structure, Decoded}}
        end
    catch 
        _:_ -> {error, json_invalid}
    end.

build_sub_prompt(Intent, Goal, Tools) ->
    ValidNames = [maps:get(<<"name">>, T) || T <- Tools],
    NamesBin = list_to_binary(lists:join(<<", ">>, ValidNames)),

    << "SYSTEM: You are a Senior AI Infrastructure Engineer.
STRICT PROTOCOL: You may ONLY use these tools: ", NamesBin/binary, "

MISSION RULES:
1. One-Stop Completion: If the goal is to list something, call the tool ONCE.
2. Immediate Exit: Once you see the tool output in the history, you MUST provide the final answer.
3. No Scope Creep: Do not check pods or deployments unless explicitly asked.
4. Stop Token: You must finish your response with a final summary.

GOAL: ", Goal/binary, "
INTENT: ", Intent/binary >>.

to_bin(B) when is_binary(B) -> B;
to_bin(V) -> iolist_to_binary(io_lib:format("~p", [V])).
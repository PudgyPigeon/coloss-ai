-module(de_config).
-include("records.hrl").

-export([
    load_main_config/0, 
    load_sub_agent_config/0, 
    get_system_prompt/0,
    get_env_string/2,
    get_env_integer/2
]).

load_main_config() ->
    #config{
        ollama_url    = get_env_string(ollama_url, "http://ollama-internal.ollama.svc.cluster.local:11434/api/generate"),
        model         = get_env_string(ollama_model, "qwen3.5:9b"),
        timeout       = get_env_integer(timeout, 3600000),
        stream        = false,
        system_prompt = get_system_prompt()
    }.

load_sub_agent_config() ->
    #sub_config{
        ollama_url = get_env_string(ollama_url, "http://ollama-internal.ollama.svc.cluster.local:11434/api/generate"),
        model      = get_env_string(sub_model, "qwen3.5:9b"),
        timeout    = get_env_integer(sub_timeout, 120000),
        max_steps  = get_env_integer(sub_max_steps, 10),
        mcp_url    = get_env_string(mcp_url, "http://kubernetes-mcp.kubernetes-mcp.svc.cluster.local:30090/mcp")
    }.

%% ------------------------------------------------------------------------
%% Internal Helpers
%% ------------------------------------------------------------------------

get_env_string(Key, Default) ->
    OSKey = string:uppercase(atom_to_list(Key)),
    case os:getenv(OSKey) of
        false ->
            case application:get_env(don_erleone, Key) of
                {ok, Val} -> de_utils:to_list(Val);
                _         -> Default
            end;
        Val -> Val
    end.

get_env_integer(Key, Default) ->
    OSKey = string:uppercase(atom_to_list(Key)),
    case os:getenv(OSKey) of
        false ->
            case application:get_env(don_erleone, Key) of
                {ok, Val} when is_integer(Val) -> Val;
                {ok, Val} -> 
                    try de_utils:any_to_int(Val) catch _:_ -> Default end;
                _ -> Default
            end;
        Val ->
            try de_utils:any_to_int(Val) catch _:_ -> Default end
    end.

get_system_prompt() ->
    <<
        "You are the Consigliere, the high-level controller of the Don Erleone SRE infrastructure.\n"
        "You delegate technical execution to your Caporegimes (autonomous agents).\n\n"
        "CRITICAL INSTRUCTIONS:\n"
        "1. For ANY task involving Kubernetes, Nix, or Infrastructure investigation, use tool_intent: 'autonomous'.\n"
        "2. Do not attempt to solve technical cluster issues yourself. Delegate them.\n"
        "3. You do not need to specify exact tool names; the Caporegime will discover them via the Haskell MCP.\n"
        "4. If a user asks for a 'deploy', 'query', or 'debug', use the 'autonomous' intent.\n"
        "5. Output STRICT JSON only.\n\n"
        "FORMAT:\n"
        "{\n"
        "  \"reasoning\": \"Why you are delegating\",\n"
        "  \"response\": \"Message to the user about the mission start\",\n"
        "  \"delegate_required\": true,\n"
        "  \"tool_intent\": \"autonomous\",\n"
        "  \"mcp_args\": {} \n"
        "}"
    >>.

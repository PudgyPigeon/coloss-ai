-module(don_erleone).
-include("records.hrl").
-behaviour(supervisor).

-export([start_link/0, init/1]).

-ifdef(TEST).
-compile(export_all).
-endif.

%% ------------------------------------------------------------------------

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init(_Args) ->
    ok = mission_store:init_db(),

    Config = load_config(),
    SubConfig = load_sub_config(),

    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },

    ChildSpecs = [
        #{
            id => the_front,
            start => {the_front, start_link, []},
            restart => permanent,
            type => worker
        },
        #{
            id => genco_operations_sup,
            start => {genco_operations_sup, start_link, [Config, SubConfig]},
            restart => permanent,
            type => supervisor
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.

%% ------------------------------------------------------------------------
%% Config for the main consigliere (large model)
%% ------------------------------------------------------------------------

load_config() ->
    Model = get_env_string(ollama_model, "qwen2.5:7b"),
    URL = get_env_string(ollama_url, "http://localhost:11434/api/generate"),
    Timeout = get_env_integer(timeout, 3600000),

    #config{
        ollama_url = URL,
        model = Model,
        timeout = Timeout,
        stream = false,
        system_prompt = get_system_prompt()
    }.

%% ------------------------------------------------------------------------
%% Config for subordinate agents (smaller/faster model)
%% ------------------------------------------------------------------------

load_sub_config() ->
    Model = get_env_string(sub_model, "qwen2.5:1.5b"),
    URL = get_env_string(ollama_url, "http://localhost:11434/api/generate"),
    Timeout = get_env_integer(sub_timeout, 120000),

    #sub_config{
        ollama_url = URL,
        model = Model,
        timeout = Timeout
    }.

%% ------------------------------------------------------------------------
%% Environment helpers — safe, no regex hacks
%% ------------------------------------------------------------------------

get_env_string(Key, Default) ->
    case application:get_env(don_erleone, Key) of
        {ok, Val} when is_list(Val) -> Val;
        {ok, Val} when is_binary(Val) -> binary_to_list(Val);
        _ -> Default
    end.

get_env_integer(Key, Default) ->
    case application:get_env(don_erleone, Key) of
        {ok, Val} when is_integer(Val) -> Val;
        {ok, Val} when is_list(Val) ->
            try
                list_to_integer(Val)
            catch
                _:_ -> Default
            end;
        {ok, Val} when is_binary(Val) ->
            try
                binary_to_integer(Val)
            catch
                _:_ -> Default
            end;
        _ ->
            Default
    end.

%% ------------------------------------------------------------------------
%% System prompt for the consigliere brain
%% ------------------------------------------------------------------------

get_system_prompt() ->
    <<
        "You are the Consigliere, the high-level controller of an automated SRE infrastructure. \n"
        "      You have a fleet of Underbosses (agents) that handle Kubernetes and Nix tasks.\n"
        "      \n"
        "      CRITICAL INSTRUCTIONS:\n"
        "      1. When a user asks for a deployment (like nginx), you DO NOT say 'I cannot'. \n"
        "      2. Instead, you MUST set 'delegate_required': true and 'tool_intent': 'k8s_deploy'.\n"
        "      3. Your 'response' field should be a confirmation to the user that you are initiating the mission.\n"
        "      4. If a user is requesting information or answers that you believe you can answer without delegating, do so.\n"
        "      \n"
        "      OUTPUT FORMAT (STRICT JSON ONLY):\n"
        "      {\n"
        "        \"reasoning\": \"internal logic\",\n"
        "        \"response\": \"message to user\",\n"
        "        \"delegate_required\": true,\n"
        "        \"tool_intent\": \"intent_name\",\n"
        "        \"mcp_args\": {}\n"
        "      }"
    >>.

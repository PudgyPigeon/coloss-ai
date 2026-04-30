-module(don_erleone).
-include("records.hrl").
-behaviour(supervisor).

-export([start_link/0, init/1]).

-ifdef(TEST).
-compile(export_all).
-endif.

%% ------------------------------------------------------------------------
%% API & Lifecycle
%% ------------------------------------------------------------------------

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init(_Args) ->
    %% 1. Initialize Mnesia Database
    case mission_store:init_db() of
        ok -> ok;
        {error, DbErr} -> logger:error("Database init failed: ~p", [DbErr])
    end,

    %% 2. Define Supervision Strategy
    SupFlags = #{
        strategy  => one_for_one,
        intensity => 5,
        period    => 10
    },

    %% 3. Load Configurations and Child Specs
    {ok, {SupFlags, get_child_specs()}}.

%% ------------------------------------------------------------------------
%% Supervision Tree Definition
%% ------------------------------------------------------------------------

get_child_specs() ->
    Config = load_main_config(),
    SubConfig = load_sub_agent_config(),
    
    [
        %% The HTTP Gateway
        #{
            id      => the_front,
            start   => {the_front, start_link, []},
            restart => permanent,
            type    => worker
        },

        %% The Orchestration Layer
        #{
            id      => the_commission,
            start   => {the_commission, start_link, [Config, SubConfig]},
            restart => permanent,
            type    => supervisor
        }
    ].

%% ------------------------------------------------------------------------
%% Configuration Logic
%% ------------------------------------------------------------------------

load_main_config() ->
    #config{
        ollama_url    = get_env_string(ollama_url, "http://localhost:11434/api/generate"),
        model         = get_env_string(ollama_model, "qwen2.5:7b"),
        timeout       = get_env_integer(timeout, 3600000),
        stream        = false,
        system_prompt = get_system_prompt()
    } .

load_sub_agent_config() ->
    #sub_config{
        ollama_url = get_env_string(ollama_url, "http://localhost:11434/api/generate"),
        model      = get_env_string(sub_model, "qwen2.5:1.5b"),
        timeout    = get_env_integer(sub_timeout, 120000)
    }.

%% ------------------------------------------------------------------------
%% Configuration Helpers
%% ------------------------------------------------------------------------

get_env_string(Key, Default) ->
    case application:get_env(don_erleone, Key) of
        {ok, Val} -> to_list(Val);
        _         -> Default
    end.

get_env_integer(Key, Default) ->
    case application:get_env(don_erleone, Key) of
        {ok, Val} when is_integer(Val) -> Val;
        {ok, Val} -> 
            try any_to_int(Val) catch _:_ -> Default end;
        _ -> Default
    end.

%% ------------------------------------------------------------------------
%% System Prompt (The Consigliere's Identity)
%% ------------------------------------------------------------------------

get_system_prompt() ->
    <<
        "You are the Consigliere, the high-level controller of an automated SRE infrastructure.\n"
        "You have a fleet of Underbosses (agents) that handle Kubernetes and Nix tasks.\n\n"
        "CRITICAL INSTRUCTIONS:\n"
        "1. DO NOT say 'I cannot'. Delegated tasks (deployments, queries) must be routed.\n"
        "2. For deployments, use tool_intent: 'k8s_deploy'.\n"
        "3. For cluster queries (pods, logs, namespaces), use tool_intent: 'k8s_query'.\n"
        "4. Confirm mission initiation in the 'response' field.\n"
        "5. Underbosses have verified cluster access via Haskell Kubernetes MCP. Do not ask for creds.\n"
        "6. Output STRICT JSON only.\n\n"
        "FORMAT:\n"
        "{\n"
        "  \"reasoning\": \"string\",\n"
        "  \"response\": \"string\",\n"
        "  \"delegate_required\": true,\n"
        "  \"tool_intent\": \"string\",\n"
        "  \"mcp_args\": {}\n"
        "}"
    >>.

%% ------------------------------------------------------------------------
%% Normalization Helpers
%% ------------------------------------------------------------------------

to_list(V) when is_binary(V) -> binary_to_list(V);
to_list(V) when is_list(V)   -> V;
to_list(V)                   -> lists:flatten(io_lib:format("~p", [V])).

any_to_int(V) when is_list(V)   -> list_to_integer(V);
any_to_int(V) when is_binary(V) -> binary_to_integer(V).
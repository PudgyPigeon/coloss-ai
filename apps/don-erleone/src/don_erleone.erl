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
        model         = get_env_string(ollama_model, "qwen3.5:9b"),
        timeout       = get_env_integer(timeout, 3600000),
        stream        = false,
        system_prompt = get_system_prompt()
    } .

load_sub_agent_config() ->
    #sub_config{
        ollama_url = get_env_string(ollama_url, "http://localhost:11434/api/generate"),
        model      = get_env_string(sub_model, "qwen3.5:9b"),
        timeout    = get_env_integer(sub_timeout, 120000),
        max_steps  = get_env_integer(sub_max_steps, 10),
        mcp_url    = get_env_string(mcp_url, "http://kubernetes-mcp.kubernetes-mcp.svc.cluster.local:8080/mcp")
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

%% ------------------------------------------------------------------------
%% Normalization Helpers
%% ------------------------------------------------------------------------

to_list(V) when is_binary(V) -> binary_to_list(V);
to_list(V) when is_list(V)   -> V;
to_list(V)                   -> lists:flatten(io_lib:format("~p", [V])).

any_to_int(V) when is_list(V)    -> list_to_integer(V);
any_to_int(V) when is_binary(V)  -> binary_to_integer(V);
any_to_int(V) when is_integer(V) -> V;
any_to_int(V) when is_atom(V)    -> any_to_int(atom_to_list(V)).
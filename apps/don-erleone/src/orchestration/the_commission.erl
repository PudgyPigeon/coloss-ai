-module(the_commission).
-behaviour(supervisor).

-export([start_link/2, init/1]).

%% ------------------------------------------------------------------------
%% API
%% ------------------------------------------------------------------------

start_link(Config, SubConfig) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [Config, SubConfig]).

%% ------------------------------------------------------------------------
%% Supervisor Initialization
%% ------------------------------------------------------------------------

init([Config, SubConfig]) ->
    %% Strategy: one_for_one
    %% Decoupling the Strategy workers from the Execution managers.
    %% We increase intensity to handle transient network/LLM flakiness.
    SupFlags = #{
        strategy  => one_for_one, 
        intensity => 10,
        period    => 60
    },

    {ok, {SupFlags, child_specs(Config, SubConfig)}}.

%% ------------------------------------------------------------------------
%% Child Definitions
%% ------------------------------------------------------------------------

child_specs(Config, SubConfig) ->
    [
        %% 1. The Underboss (Fleet Manager for Caporegimes)
        %% This handles the 'Shell' side of the Autonomous Loop.
        #{
            id      => underboss,
            start   => {underboss, start_link, [SubConfig]},
            restart => permanent,
            type    => supervisor
        },

        %% 2. The Consigliere Pool (Strategy Workers)
        %% This handles the 'Shell' side of the LLM Strategy.
        poolboy:child_spec(consigliere_pool, pool_config(), [Config])
    ].

%% ------------------------------------------------------------------------
%% Internal Configuration
%% ------------------------------------------------------------------------

pool_config() ->
    [
        {name, {local, consigliere_pool}},
        {worker_module, consigliere_worker},
        {size, 5},           %% Static workers always ready
        {max_overflow, 15},  %% Expanded overflow for busy SRE shifts
        {strategy, fifo}     %% Ensure we don't 'wear out' the first worker in the pool
    ].
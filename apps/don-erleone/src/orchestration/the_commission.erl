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
    %% Strategy: rest_for_one
    %% If the Underboss (first child) dies, the Consigliere Pool (second child) 
    %% is restarted automatically to ensure consistent state.
    SupFlags = #{
        strategy  => rest_for_one,
        intensity => 5,
        period    => 10
    },

    {ok, {SupFlags, child_specs(Config, SubConfig)}}.

%% ------------------------------------------------------------------------
%% Child Definitions
%% ------------------------------------------------------------------------

child_specs(Config, SubConfig) ->
    [
        %% 1. The Underboss (Hierarchy: Manager of Caporegimes)
        #{
            id      => underboss,
            start   => {underboss, start_link, [SubConfig]},
            restart => permanent,
            type    => supervisor
        },

        %% 2. The Consigliere Pool (Hierarchy: Strategy Workers)
        poolboy:child_spec(consigliere_pool, pool_config(), [Config])
    ].

%% ------------------------------------------------------------------------
%% Internal Configuration
%% ------------------------------------------------------------------------

pool_config() ->
    [
        {name, {local, consigliere_pool}},
        {worker_module, consigliere_worker},
        {size, 5},
        {max_overflow, 10}
    ].
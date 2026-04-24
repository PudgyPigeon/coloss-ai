-module(genco_operations_sup).
-behaviour(supervisor).

-export([start_link/2, init/1]).

%% ------------------------------------------------------------------------

start_link(Config, SubConfig) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [Config, SubConfig]).

init([Config, SubConfig]) ->
    
    PoolArgs = [
        {name, {local, consigliere_pool}},
        {worker_module, consigliere_worker},
        {size, 5},
        {max_overflow, 10}
    ],

    %% rest_for_one guarantees that if the Underboss dies, 
    %% the Consigliere Pool is restarted to prevent zombie references.
    SupFlags = #{
        strategy => rest_for_one,
        intensity => 5,
        period => 10
    },

    %% Order is strictly required! 
    ChildSpecs = [
        #{
            id => underboss,
            start => {underboss, start_link, [SubConfig]},
            restart => permanent,
            type => supervisor
        },
        poolboy:child_spec(consigliere_pool, PoolArgs, [Config])
    ],

    {ok, {SupFlags, ChildSpecs}}.
-module(de_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy  => one_for_one,
        intensity => 5,
        period    => 10
    },

    %% Load Configurations
    Config = de_config:load_main_config(),
    SubConfig = de_config:load_sub_agent_config(),

    ChildSpecs = [
        %% The HTTP Gateway
        #{
            id      => de_front,
            start   => {de_front, start_link, []},
            restart => permanent,
            type    => worker
        },

        %% The Orchestration Layer
        #{
            id      => de_commission,
            start   => {de_commission, start_link, [Config, SubConfig]},
            restart => permanent,
            type    => supervisor
        }
    ],

    {ok, {SupFlags, ChildSpecs}}.

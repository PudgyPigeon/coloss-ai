-module(caporegime).

-behaviour(supervisor).

-export([start_link/1, init/1]).

start_link(Type) ->
    supervisor:start_link(?MODULE, [Type]).

init([Type]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 3,
        period => 5
    },
    ChildSpecs = [
        #{
            id => lieutenant,
            start => {lieutenant, start_link, [Type]}
        },
        #{
            id => recruiter,
            start => {recruiter, start_link, []},
            type => supervisor
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.

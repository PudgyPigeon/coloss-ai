-module(underboss).
-behaviour(supervisor).

-export([start_link/0, recruit_sub_agent/1, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

recruit_sub_agent(Type) ->
    supervisor:start_child(?MODULE, [Type]).

init([]) ->
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 10,
        period => 5
    },
    ChildSpecs = [
        #{
            id => caporegime,
            start => {caporegime, start_link, []},
            type => supervisor
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.

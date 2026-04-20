-module(agent_sup).

-behaviour(supervisor).

-export([start_link/0, init/1, start_agent/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_agent(AgentId) ->
    supervisor:start_child(?MODULE, [AgentId]).

init([]) ->
    SupFlags =
        #{strategy => simple_one_for_one,
          intensity => 10,
          period => 60},
    ChildSpecs =
        [#{id => agent_worker,
           start => {agent_worker, start_link, []},
           restart => temporary}],
    {ok, {SupFlags, ChildSpecs}}.

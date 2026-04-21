-module(don_erleone).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init(_Args) ->
    SupFlags =
        #{strategy => one_for_one,
          intensity => 5,
          period => 10},
    ChildSpecs =
        [#{id => the_front, start => {the_front, start_link, []}},
         #{id => consigliere, start => {consigliere, start_link, []}}], %,
    % #{id => underboss,       start => {underboss, start_link, []}, type => supervisor}
    {ok, {SupFlags, ChildSpecs}}.

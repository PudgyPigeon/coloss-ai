-module(recruiter).

-behaviour(supervisor).

-export([start_link/0, recruit/2, init/1]).

%% The Caporegime starts this without a name because
%% there is one Recruiter per Sub-agent crew.
start_link() -> supervisor:start_link(?MODULE, []).

%% The Lieutenant calls this to spawn an Associate
recruit(RecruiterPid, {LtPid, Contract}) ->
    supervisor:start_child(RecruiterPid, [LtPid, Contract]).

init([]) ->
    %% simple_one_for_one is the standard for dynamic worker pools
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 10,
        period => 5
    },
    ChildSpecs = [
        #{
            id => associate,
            start => {associate, start_link, []},
            restart =>
                %% If a hit fails, we don't automatically retry it
                temporary,
            type => worker
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.

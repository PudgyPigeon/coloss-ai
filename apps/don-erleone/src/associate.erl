-module(associate).

-behaviour(gen_server).

-export([start_link/2, init/1, handle_info/2]).

%% start_link is called by the recruiter with the arguments [LtPid, Contract]
start_link(LtPid, Contract) ->
    gen_server:start_link(?MODULE, [LtPid, Contract], []).

init([LtPid, Contract]) ->
    %% Do the work asynchronously
    self() ! execute,
    {ok, {LtPid, Contract}}.

handle_info(execute, {LtPid, Contract}) ->
    io:format("[Associate] Executing hit: ~p~n", [Contract]),

    %% 1. CALL OLLAMA (Local LLM Reasoning)
    %% 2. CALL HASKELL MCP (The Tool)
    %% Simulate work
    timer:sleep(1000),

    %% Report back to the specific Lieutenant of this crew
    lieutenant:report_back(LtPid, <<"Success">>),

    %% Die gracefully. The recruiter won't restart a 'temporary' child.
    {stop, normal, ok}.

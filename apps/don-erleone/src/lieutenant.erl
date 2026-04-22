-module(lieutenant).

-behaviour(gen_server).

-export([
    start_link/1,
    assign_contract/2,
    report_back/2,
    init/1,
    handle_call/3,
    handle_cast/2
]).

start_link([Type]) ->
    gen_server:start_link(?MODULE, [Type], []).

assign_contract(Pid, Contract) ->
    gen_server:call(Pid, {contract, Contract}).

report_back(Pid, Result) ->
    gen_server:cast(Pid, {done, Result}).

init([Type]) ->
    {ok, #{role => Type, active_tasks => 0}}.

handle_call({contract, C}, _From, State) ->
    %% Recruit an Associate to use the Haskell MCP tool
    {ok, _} = recruiter:recruit(self(), C),
    {reply, ok, State#{active_tasks => 1}}.

handle_cast({done, Res}, State) ->
    %% Report finished work back to the Consigliere
    consigliere ! {mission_complete, Res},
    {noreply, State#{active_tasks => 0}}.

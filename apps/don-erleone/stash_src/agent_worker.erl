-module(agent_worker).

-behaviour(gen_server).

-export([start_link/1, init/1, handle_info/2, handle_call/3, handle_cast/2]).

start_link(AgentId) ->
    gen_server:start_link(?MODULE, [AgentId], []).

init([AgentId]) ->
    %% SRE Trick: Start the reconciliation loop immediately
    self() ! reconcile,
    {ok, #{id => AgentId, last_check => erlang:system_time(seconds)}}.

handle_info(reconcile, State) ->
    %% ARCHITECT LOGIC: Verify system state (e.g., check GPU/Nix status)
    io:format("Reconciling Agent: ~p~n", [maps:get(id, State)]),

    %% Schedule next check (5 seconds)
    erlang:send_after(30000, self(), reconcile),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

handle_call(_Req, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

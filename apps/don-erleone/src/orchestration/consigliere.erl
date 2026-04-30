-module(consigliere).
-export([handle_mission/3]).

-ifdef(TEST).
-compile(export_all).
-endif.

%% ------------------------------------------------------------------------
%% API
%% ------------------------------------------------------------------------

%% Dispatches a mission to the consigliere pool asynchronously.
%% CowboyFrom = {Pid, Tag} — the cowboy handler blocks on receive for this Tag.
handle_mission(SessionId, Prompt, CowboyFrom) ->
    proc_lib:spawn(fun() -> async_pool_consult(SessionId, Prompt, CowboyFrom) end),
    ok.

%% ------------------------------------------------------------------------
%% Internal Helpers
%% ------------------------------------------------------------------------

async_pool_consult(SessionId, Prompt, CowboyFrom) ->
    try
        execute_transaction(SessionId, Prompt, CowboyFrom)
    catch
        Class:Error:Stack ->
            handle_dispatch_error(CowboyFrom, Class, Error, Stack)
    end.

execute_transaction(SessionId, Prompt, CowboyFrom) ->
    poolboy:transaction(consigliere_pool, fun(Worker) ->
        gen_server:call(Worker, {consult, SessionId, Prompt, CowboyFrom}, infinity)
    end).

handle_dispatch_error({Pid, Tag}, Class, Error, Stack) ->
    %% 1. Log the failure
    logger:error("Consigliere pool dispatch failed: ~p:~p~n~p", 
                 [Class, Error, Stack]),
    
    %% 2. Unblock the cowboy handler so it doesn't hang
    Pid ! {Tag, {error, {pool_dispatch_error, Error}}}.
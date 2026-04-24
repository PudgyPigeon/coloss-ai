-module(consigliere).
-export([handle_mission/3]).

%% Dispatches a mission to the consigliere pool asynchronously.
%% CowboyFrom = {Pid, Tag} — the cowboy handler blocks on receive for this Tag.
handle_mission(SessionId, Prompt, CowboyFrom) ->
    proc_lib:spawn(fun() -> do_dispatch(SessionId, Prompt, CowboyFrom) end),
    ok.

%% --- Internal Helpers ---

do_dispatch(SessionId, Prompt, CowboyFrom) ->
    try
        poolboy:transaction(consigliere_pool, fun(Worker) ->
            gen_server:call(Worker, {consult, SessionId, Prompt, CowboyFrom}, infinity)
        end)
    catch
        Class:Error:Stack ->
            logger:error("Consigliere pool dispatch failed: ~p:~p~n~p",
                         [Class, Error, Stack]),
            %% Unblock the cowboy handler so it doesn't hang for 120s
            {CowboyPid, CowboyTag} = CowboyFrom,
            CowboyPid ! {CowboyTag, {error, {pool_error, Error}}}
    end.
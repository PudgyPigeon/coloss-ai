-module(consigliere).
-export([handle_mission/3]).

handle_mission(SessionId, Prompt, From) ->
    spawn(fun() ->
        poolboy:transaction(consigliere_pool, fun(Worker) ->
            %% We use call to ensure the worker is actually acquired 
            %% and finishes its routine before the transaction ends.
            gen_server:call(Worker, {consult, SessionId, Prompt, From}, infinity)
        end)
    end),
    ok. %% Return 'ok' so the handler proceeds to the 'receive' block
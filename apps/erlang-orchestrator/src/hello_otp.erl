-module(hello_otp).

-behaviour(supervisor).
-behaviour(gen_server).

%% API
-export([start/0, increment/0, get_value/0]).
%% Callbacks
-export([init/1, handle_call/3]).

%% API - what the user calls
%% starts the supervisor, which starts the worker
start() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, supervisor_init).

increment() ->
    gen_server:call(worker_process, add).

get_value() ->
    gen_server:call(worker_process, read).

%% The supervisor - the manager of the gen-servers(?)/workers
%% This defines how the worker should be started and protected
init(supervisor_init) ->
    SupFlags =
        #{strategy => one_for_one,
          intensity => 1,
          period => 5},
    ChildSpecs =
        [#{id => worker_process,
           start => {gen_server, start_link, [{local, worker_process}, ?MODULE, worker_init, []]}}],
    {ok, {SupFlags, ChildSpecs}};
%% The Gen_server (the worker)
%% This is the worker's init. It starts with a count of 0
init(worker_init) ->
    {ok, 0}. %% InitialCount

%% React to 'add': NewState = Count + 1. Reply with 'ok'
%% Function below that is pattern matching - React to read: state stays the same. reply with count
handle_call(add, _From, Count) ->
    {reply, ok, Count + 1};
handle_call(read, _From, Count) ->
    {reply, Count, Count}.

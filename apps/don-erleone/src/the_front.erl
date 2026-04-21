-module(the_front).
-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    %% SRE Note: {active, false} means we manually control the socket flow.
    {ok, LSock} = gen_tcp:listen(8080, [binary, {packet, line}, {active, false}, {reuseaddr, true}]),
    io:format("The Front is now Multi-User on port 8080...~n"),

    %% Kick off the first acceptor loop
    self() ! accept,
    {ok, #{lsock => LSock}}.

%% --- Mandatory Callbacks to satisfy the compiler ---

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

%% --- The Acceptor Logic ---

handle_info(accept, State = #{lsock := LSock}) ->
    case gen_tcp:accept(LSock) of
        {ok, Socket} ->
            %% Spawn the worker so the Host stays at the door
            spawn(fun() -> handle_customer(Socket) end),
            %% Loop back to accept more connections
            self() ! accept;
        {error, _Reason} ->
            self() ! accept
    end,
    {noreply, State};

handle_info(_Msg, State) ->
    {noreply, State}.

%% --- The "Waiter" Worker ---

handle_customer(Socket) ->
    %% Since init used {active, false}, we use gen_tcp:recv here
    case gen_tcp:recv(Socket, 0) of
        {ok, Data} ->
            Contract = string:trim(Data),
            io:format("The Front: Processing request for ~s~n", [Contract]),

            %% Call the brain (Consigliere)
            case consigliere:handle_mission(Contract) of
                {ok, Result} ->
                    gen_tcp:send(Socket, [<<"Processed: ">>, Result, <<"\n">>]);
                {error, Reason} ->
                    gen_tcp:send(Socket, [<<"Error: ">>, io_lib:format("~p", [Reason]), <<"\n">>]);
                Other ->
                    gen_tcp:send(Socket, [<<"Raw: ">>, io_lib:format("~p", [Other]), <<"\n">>])
            end;
        {error, closed} ->
            ok;
        _Error ->
            ok
    end,
    gen_tcp:close(Socket).

terminate(_Reason, #{lsock := LSock}) ->
    gen_tcp:close(LSock).
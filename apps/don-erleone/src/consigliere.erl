-module(consigliere).
-behaviour(gen_server).

%% API
-export([start_link/0, handle_mission/1, delegate_task/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% --- API ---

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Standardizing your API names
handle_mission(Prompt) ->
    io:format("Calling handle_mission~n"),
    gen_server:call(?MODULE, {ollama, Prompt}).

delegate_task(Input) ->
    gen_server:call(?MODULE, {process, Input}).

% ask_ollama(Prompt) ->
%     handle_mission(Prompt).

%% --- Callbacks ---

init([]) ->
    %% Start the inets application for httpc
    inets:start(),
    {ok, #{}}.

%% Handle Ollama requests
handle_call({ollama, Prompt}, _From, State) ->
    io:format("Consigliere: Attempting to reach Ollama for: ~p~n", [Prompt]),
    Data = #{<<"model">> => <<"llama3">>, 
             <<"prompt">> => Prompt,
             <<"stream">> => false},
    Body = jsx:encode(Data),
    URL = "http://localhost:11434/api/generate",
    
    case httpc:request(post, {URL, [], "application/json", Body}, [], [{timeout, 5000}]) of
        {ok, {{_, 200, _}, _Headers, RespBody}} ->
            FullMap = jsx:decode(RespBody, [return_maps]),
            TextResponse = maps:get(<<"response">>, FullMap, <<"No response field found">>),
            {reply, {ok, TextResponse}, State};
        
        %% Catching the "Server Down" scenario specifically
        {error, econnrefused} ->
            io:format("Consigliere ERROR: Ollama server is not running (econnrefused).~n"),
            {reply, {error, "The Brain is currently sleeping (Ollama offline)."}, State};

        {error, timeout} ->
            {reply, {error, "Ollama took too long to think."}, State};

        {error, Reason} ->
            io:format("Consigliere ERROR: ~p~n", [Reason]),
            {reply, {error, io_lib:format("Internal Syndicate Error: ~p", [Reason])}, State}
    end;

%% Handle Task Delegation
handle_call({process, Input}, _From, State) ->
    io:format("Consigliere: Processing logic for ~p~n", [Input]),
    {reply, ok, State};

%% Catch-all for other calls
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

%% Required callback: handle_cast
handle_cast(_Msg, State) ->
    {noreply, State}.

%% Required callback: handle_info
handle_info(_Msg, State) ->
    {noreply, State}.

    %% Handle call and handle info are lifecycle hooks that are built into
                                                                                                                                                                                                                                                                                                                                                                                                                                        %% the OTP framework - we just define behaviour and traits for this module's
                                                                                                                                                                                                                                                                                                                                                                                                                                        %% implementation
                                                                                                                                                                                                                                                                                                                                                                                                                                        %% Build JSON request body
    %% Send HTTP post to Ollama

    %% Decode response

% -module(consigliere).
% -behaviour(gen_server).
% -export([start_link/0, handle_hit/1, init/1, handle_call/3, handle_info/2]).

% start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
% handle_hit(Input) -> gen_server:call(?MODULE, {process, Input}).

% init([]) ->
%     {ok, _Redis} = eredis:start_link(), %% Local Redis for context
%     {ok, #{archives => _Redis, active_missions => #{}}}.

% handle_call({process, Input}, _From, State) ->
%     %% 1. Brain Reasons (Simple mock: LLM would decide which tool is needed)
%     %% In a real swarm, you'd ask Ollama "Which sub-agent do I need for this?"
%     TaskType = k8s_specialist,

%     %% 2. Brain delegates to the Underboss
%     {ok, SubAgentPid} = underboss:recruit_sub_agent(TaskType),

%     %% 3. Brain instructs the Sub-agent's Lieutenant
%     lieutenant:assign_contract(SubAgentPid, #{goal => Input}),

%     {reply, {ok, mission_started, SubAgentPid}, State}.

% handle_info({mission_complete, Data}, State) ->
%     io:format("Consigliere: Mission result received: ~p~n", [Data]),
%     {noreply, State}.

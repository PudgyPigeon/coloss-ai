-module(mission_store).
-include("records.hrl").

-export([
    init_db/0,
    post_mission/4,
    get_mission/1,
    get_latest_context/1,
    update_status/2,
    complete_mission/2,
    fail_mission/2,
    get_pending_missions/0
]).

%% ------------------------------------------------------------------------
%% Database Lifecycle
%% ------------------------------------------------------------------------

init_db() ->
    logger:info(#{event => db_init_start}),
    _ = mnesia:start(),
    TableDef = [
        {attributes, record_info(fields, mission)},
        {index, [session_id, status]},
        {ram_copies, [node()]}
    ],
    ensure_table(mission, TableDef).

ensure_table(Name, Def) ->
    case mnesia:create_table(Name, Def) of
        {atomic, ok} -> 
            logger:info(#{event => table_created, table => Name}),
            mnesia:wait_for_tables([Name], 5000);
        {aborted, {already_exists, Name}} -> 
            mnesia:wait_for_tables([Name], 5000);
        {aborted, Reason} -> 
            logger:error(#{event => table_creation_failed, table => Name, error => Reason}),
            {error, Reason}
    end.

%% ------------------------------------------------------------------------
%% Public API (Orchestration)
%% ------------------------------------------------------------------------

post_mission(SessionId, Intent, Prompt, Context) ->
    Id = erlang:unique_integer([positive, monotonic]),
    Record = #mission{
        id = Id,
        session_id = SessionId,
        intent = Intent,
        raw_prompt = Prompt,
        status = pending,
        context_tokens = Context,
        timestamp = erlang:system_time(second)
    },
    execute_write(Record, Id).

get_mission(Id) ->
    execute_read(Id).

get_latest_context(SessionId) ->
    case mnesia:dirty_index_read(mission, SessionId, #mission.session_id) of
        [] -> [];
        List -> 
            Sorted = sort_by_timestamp(List),
            extract_context(hd(Sorted))
    end.

update_status(MissionId, NewStatus) ->
    modify_mission(MissionId, fun(R) -> R#mission{status = NewStatus} end).

complete_mission(MissionId, Result) ->
    modify_mission(MissionId, fun(R) -> R#mission{status = completed, result = Result} end).

fail_mission(MissionId, Error) ->
    modify_mission(MissionId, fun(R) -> R#mission{status = failed, error = Error} end).

get_pending_missions() ->
    Trans = fun() -> mnesia:index_read(mission, pending, #mission.status) end,
    case mnesia:transaction(Trans) of
        {atomic, Results} -> {ok, Results};
        {aborted, Reason} -> {error, Reason}
    end.

%% ------------------------------------------------------------------------
%% Internal Transaction Logic (The "Functional" Chunks)
%% ------------------------------------------------------------------------

%% Generic record modifier
modify_mission(Id, UpdateFun) ->
    Trans = fun() ->
        case mnesia:read(mission, Id) of
            [Record] -> mnesia:write(UpdateFun(Record));
            [] -> {error, not_found}
        end
    end,
    case mnesia:transaction(Trans) of
        {atomic, ok} -> ok;
        {atomic, {error, _} = Err} -> Err;
        {aborted, Reason} -> {error, Reason}
    end.

execute_write(Record, Id) ->
    case mnesia:transaction(fun() -> mnesia:write(Record) end) of
        {atomic, ok} -> {ok, Id};
        {aborted, Reason} -> 
            logger:error(#{event => db_write_failed, mission_id => Id, error => Reason}),
            {error, Reason}
    end.

execute_read(Id) ->
    case mnesia:transaction(fun() -> mnesia:read(mission, Id) end) of
        {atomic, [Result]} -> {ok, Result};
        {atomic, []} -> {error, not_found};
        {aborted, Reason} -> 
            logger:error(#{event => db_read_failed, mission_id => Id, error => Reason}),
            {error, Reason}
    end.

%% ------------------------------------------------------------------------
%% Pure Helpers
%% ------------------------------------------------------------------------

sort_by_timestamp(List) ->
    lists:sort(fun(A, B) -> A#mission.timestamp > B#mission.timestamp end, List).

extract_context(#mission{context_tokens = undefined}) -> [];
extract_context(#mission{context_tokens = Tokens}) -> Tokens.
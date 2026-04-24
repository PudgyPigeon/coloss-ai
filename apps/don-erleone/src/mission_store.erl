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

%% ram_copies for POC — switch to disc_copies for production durability
init_db() ->
    _ = mnesia:start(),
    case 
        mnesia:create_table(mission, [
            {attributes, record_info(fields, mission)},
            {index, [session_id, status]},
            {ram_copies, [node()]}
        ])
    of
        {atomic, ok} ->
            mnesia:wait_for_tables([mission], 5000);
        {aborted, {already_exists, mission}} ->
            mnesia:wait_for_tables([mission], 5000);
        {aborted, Reason} -> {error, Reason}
    end.

post_mission(SessionId, Intent, Prompt, Context) ->
    %% Using unique monotonic integers generates cleaner IDs for JSON than make_ref()
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
    F = fun() -> mnesia:write(Record) end,
    case mnesia:transaction(F) of
        {atomic, ok} -> {ok, Id};
        {aborted, Reason} -> {error, Reason}
    end.

get_mission(Id) ->
    F = fun() -> mnesia:read(mission, Id) end,
    case mnesia:transaction(F) of
        {atomic, [Result]} -> {ok, Result};
        {atomic, []} -> {error, not_found};
        {aborted, Reason} -> {error, Reason}
    end.

get_latest_context(SessionId) ->
    case mnesia:dirty_index_read(mission, SessionId, #mission.session_id) of
        [] ->
            [];
        List ->
            Sorted = lists:sort(
                fun(A, B) -> A#mission.timestamp > B#mission.timestamp end,
                List
            ),
            case (hd(Sorted))#mission.context_tokens of
                undefined -> [];
                Tokens -> Tokens
            end
    end.

update_status(MissionId, NewStatus) ->
    F = fun() ->
        case mnesia:read(mission, MissionId) of
            [Record] ->
                mnesia:write(Record#mission{status = NewStatus});
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok} -> ok;
        {atomic, {error, _} = Err} -> Err;
        {aborted, Reason} -> {error, Reason}
    end.

complete_mission(MissionId, Result) ->
    F = fun() ->
        case mnesia:read(mission, MissionId) of
            [Record] ->
                mnesia:write(Record#mission{
                    status = completed,
                    result = Result
                });
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok} -> ok;
        {atomic, {error, _} = Err} -> Err;
        {aborted, Reason} -> {error, Reason}
    end.

fail_mission(MissionId, Error) ->
    F = fun() ->
        case mnesia:read(mission, MissionId) of
            [Record] ->
                mnesia:write(Record#mission{
                    status = failed,
                    error = Error
                });
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok} -> ok;
        {atomic, {error, _} = Err} -> Err;
        {aborted, Reason} -> {error, Reason}
    end.

get_pending_missions() ->
    F = fun() ->
        mnesia:index_read(mission, pending, #mission.status)
    end,
    case mnesia:transaction(F) of
        {atomic, Results} -> {ok, Results};
        {aborted, Reason} -> {error, Reason}
    end.

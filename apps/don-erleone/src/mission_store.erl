-module(mission_store).

-include("records.hrl").

-export([init_db/0, post_mission/4, get_mission/1, get_latest_context/1]).

%% disc_copies -> Persist to disk for durability % RAM for POC
init_db() ->
    case
        mnesia:create_table(mission, [
            {attributes, record_info(fields, mission)},
            {index, [session_id]},
            {ram_copies, [node()]}
        ])
    of
        {atomic, ok} -> ok;
        {aborted, {already_exists, mission}} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

post_mission(SessionId, Intent, Prompt, Context) ->
    Id = make_ref(),
    Record = #mission{
        id = Id,
        session_id = SessionId,
        intent = Intent,
        raw_prompt = Prompt,
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
            %% Sort by timestamp descending and pick the newest
            Sorted = lists:sort(fun(A, B) -> A#mission.timestamp > B#mission.timestamp end, List),
            (hd(Sorted))#mission.context_tokens
    end.

get_pending() ->
    ok.

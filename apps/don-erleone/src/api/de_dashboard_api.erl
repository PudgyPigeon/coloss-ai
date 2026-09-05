%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

-module(de_dashboard_api).

-export([get_metrics/0, get_recent_missions/1, get_supervision_tree/0]).

%% =============================================================================
%% API: Operational Metrics (LiveView Deck)
%% =============================================================================

-spec get_metrics() -> map().
get_metrics() ->
    Consigliere = get_pool_status(de_consigliere_pool, 5, 15),
    Caporegime = get_pool_status(de_caporegime_pool, 3, 10),
    Memory = erlang:memory(total),
    Procs = erlang:system_info(process_count),
    RunQueue = erlang:statistics(run_queue),

    #{
        consigliere => Consigliere,
        caporegime => Caporegime,
        system_vitals => #{
            memory_bytes => Memory,
            process_count => Procs,
            run_queue => RunQueue
        }
    }.

-spec get_pool_status(atom(), integer(), integer()) -> map().
get_pool_status(PoolName, DefaultSize, DefaultOverflow) ->
    Status = catch poolboy:status(PoolName),
    format_pool_status(Status, DefaultSize, DefaultOverflow).

-spec format_pool_status(term(), integer(), integer()) -> map().
format_pool_status({StatusAtom, Active, Idle, Overflow}, DefaultSize, DefaultOverflow) when is_atom(StatusAtom) ->
    #{
        active => Active,
        idle => Idle,
        overflow => Overflow,
        max_size => DefaultSize,
        max_overflow => DefaultOverflow,
        status => StatusAtom
    };
format_pool_status(_, DefaultSize, DefaultOverflow) ->
    #{
        active => 0,
        idle => DefaultSize,
        overflow => 0,
        max_size => DefaultSize,
        max_overflow => DefaultOverflow,
        status => offline
    }.

%% =============================================================================
%% API: Mission Ledgers
%% =============================================================================

-spec get_recent_missions(integer()) -> [map()].
get_recent_missions(Limit) ->
    Missions = catch mnesia:dirty_select(mission, [{'_', [], ['$_']}]),
    handle_missions(Missions, Limit).

-spec handle_missions(list() | term(), integer()) -> [map()].
handle_missions(List, Limit) when is_list(List) ->
    %% Sort descending by timestamp
    Sorted = lists:sort(
        fun(A, B) ->
            %% mission record tuple element 10 is timestamp
            element(10, A) > element(10, B)
        end,
        List
    ),
    Truncated = lists:sublist(Sorted, Limit),
    [format_mission(M) || M <- Truncated];
handle_missions(_, _Limit) ->
    [].

-spec format_mission(tuple()) -> map().
format_mission(MissionTuple) ->
    %% Record format: {mission, id, session_id, intent, raw_prompt, status, result, error, context_tokens, timestamp}
    #{
        id => element(2, MissionTuple),
        session_id => element(3, MissionTuple),
        intent => element(4, MissionTuple),
        raw_prompt => element(5, MissionTuple),
        status => element(6, MissionTuple),
        result => format_term(element(7, MissionTuple)),
        error => format_term(element(8, MissionTuple)),
        timestamp => element(10, MissionTuple)
    }.

-spec format_term(term()) -> binary().
format_term(undefined) -> <<"nil">>;
format_term(Term) when is_binary(Term) -> Term;
format_term(Term) -> iolist_to_binary(io_lib:format("~p", [Term])).

%% =============================================================================
%% API: Supervision Tree (BEAM VM true state)
%% =============================================================================

-spec get_supervision_tree() -> map().
get_supervision_tree() ->
    {Nodes, Links} = walk_tree(de_sup, de_sup, undefined, [], []),
    #{nodes => Nodes, links => Links}.

-spec walk_tree(term(), atom() | pid(), undefined | binary(), [map()], [map()]) -> {[map()], [map()]}.
walk_tree(Id, PidOrName, ParentId, AccNodes, AccLinks) ->
    Children = catch supervisor:which_children(PidOrName),
    handle_children(Children, Id, PidOrName, ParentId, AccNodes, AccLinks).

-spec handle_children(list() | term(), term(), atom() | pid(), undefined | binary(), [map()], [map()]) ->
    {[map()], [map()]}.
handle_children(Children, Id, PidOrName, ParentId, AccNodes, AccLinks) when is_list(Children) ->
    NodeId = format_id(PidOrName),
    Node = #{id => NodeId, name => format_name(Id), type => supervisor},

    NewNodes = [Node | AccNodes],
    NewLinks = link_to_parent(ParentId, NodeId, AccLinks),

    lists:foldl(
        fun({Id, ChildPid, Type, _}, {NAcc, LAcc}) ->
            process_child(Type, Id, ChildPid, NodeId, NAcc, LAcc)
        end,
        {NewNodes, NewLinks},
        Children
    );
handle_children(_, _Id, _PidOrName, _ParentId, AccNodes, AccLinks) ->
    {AccNodes, AccLinks}.

-spec link_to_parent(undefined | binary(), binary(), [map()]) -> [map()].
link_to_parent(undefined, _NodeId, AccLinks) ->
    AccLinks;
link_to_parent(ParentId, NodeId, AccLinks) ->
    [#{source => ParentId, target => NodeId} | AccLinks].

-spec process_child(atom(), term(), pid() | atom() | term(), binary(), [map()], [map()]) ->
    {[map()], [map()]}.
process_child(supervisor, Id, ChildPid, ParentId, AccNodes, AccLinks) when
    is_pid(ChildPid); is_atom(ChildPid)
->
    walk_tree(Id, ChildPid, ParentId, AccNodes, AccLinks);
process_child(_Type, de_consigliere_pool, ChildPid, ParentId, AccNodes, AccLinks) ->
    ChildNodeId = format_id(ChildPid),
    WNode = #{id => ChildNodeId, name => <<"de_consigliere_pool">>, type => worker},
    WLink = #{source => ParentId, target => ChildNodeId},
    Status = get_pool_status(de_consigliere_pool, 5, 15),
    generate_pseudo_workers(
        <<"consigliere">>, maps:get(active, Status), maps:get(idle, Status),
        ChildNodeId, [WNode | AccNodes], [WLink | AccLinks]
    );
process_child(_Type, de_caporegime_pool, ChildPid, ParentId, AccNodes, AccLinks) ->
    ChildNodeId = format_id(ChildPid),
    WNode = #{id => ChildNodeId, name => <<"de_caporegime_pool">>, type => worker},
    WLink = #{source => ParentId, target => ChildNodeId},
    Status = get_pool_status(de_caporegime_pool, 3, 10),
    generate_pseudo_workers(
        <<"caporegime">>, maps:get(active, Status), maps:get(idle, Status),
        ChildNodeId, [WNode | AccNodes], [WLink | AccLinks]
    );
process_child(_Type, Id, ChildPid, ParentId, AccNodes, AccLinks) ->
    ChildNodeId = format_id(ChildPid),
    WNode = #{id => ChildNodeId, name => format_name(Id), type => worker},
    WLink = #{source => ParentId, target => ChildNodeId},
    {[WNode | AccNodes], [WLink | AccLinks]}.

-spec generate_pseudo_workers(binary(), integer(), integer(), binary(), [map()], [map()]) ->
    {[map()], [map()]}.
generate_pseudo_workers(Prefix, ActiveCount, IdleCount, ParentId, Nodes, Links) ->
    {ActNodes, ActLinks} = create_pool_entities(Prefix, ParentId, ActiveCount, <<"_act_">>, pool_active),
    {IdlNodes, IdlLinks} = create_pool_entities(Prefix, ParentId, IdleCount, <<"_idl_">>, pool_idle),

    {ActNodes ++ IdlNodes ++ Nodes, ActLinks ++ IdlLinks ++ Links}.

-spec create_pool_entities(binary(), binary(), integer(), binary(), atom()) -> {[map()], [map()]}.
create_pool_entities(Prefix, ParentId, Count, Suffix, Type) ->
    Nodes = [
        #{
            id => iolist_to_binary([Prefix, Suffix, integer_to_binary(Idx)]),
            name => Prefix,
            type => Type
        }
     || Idx <- lists:seq(1, Count)
    ],
    Links = [
        #{
            source => ParentId,
            target => iolist_to_binary([Prefix, Suffix, integer_to_binary(Idx)])
        }
     || Idx <- lists:seq(1, Count)
    ],
    {Nodes, Links}.

-spec format_id(pid() | atom() | term()) -> binary().
format_id(Pid) when is_pid(Pid) -> iolist_to_binary(io_lib:format("~p", [Pid]));
format_id(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
format_id(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

-spec format_name(pid() | atom() | term()) -> binary().
format_name(Pid) when is_pid(Pid) -> iolist_to_binary(io_lib:format("~p", [Pid]));
format_name(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
format_name(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

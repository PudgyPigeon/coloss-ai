%% SPDX-License-Identifier: AGPL-3.0-or-later
%% Copyright (C) 2026 Tommy (Thae Hyun) Nam <tommynam1994@gmail.com>

%% Global config for the main consigliere brain
-record(config, {
    ollama_url    :: string(),
    model         :: string(),
    timeout       :: integer(),
    stream        :: boolean(),
    system_prompt :: binary()
}).

%% Config for sub-agent (caporegime) Ollama calls — smaller/faster models
-record(sub_config, {
    ollama_url :: string(),
    mcp_url    :: string(),
    model      :: string(),
    timeout    :: integer(),
    max_steps  :: integer()
}).

%% The mission ledger entry
-record(mission, {
    id,               %% Unique reference (ref or uuid)
    session_id,       %% Identify which user/session this belongs to
    intent,           %% k8s_status, check_mcp, etc.
    raw_prompt,       %% Original user input
    status = pending, %% pending, in_progress, completed, failed
    result,           %% Final result from sub-agents
    error,            %% Error reason if failed
    context_tokens,   %% Store the Ollama 'context' array here
    timestamp
}).

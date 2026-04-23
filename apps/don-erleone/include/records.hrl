%% Global config for the agent
-record(config, {
    ollama_url   :: string(),
    model        :: string(),
    timeout      :: integer(),
    stream       :: boolean(), 
    systemPrompt :: binary()
}).

%% The mission ledger entry
-record(mission, {
    id,               %% Unique reference (ref or uuid)
    session_id,       %% Identify which user/session this belongs to
    intent,           %% k8s_status, check_mcp, etc.
    raw_prompt,       %% Original user input
    status = pending, %% pending, in_progress, completed, failed
    context_tokens,   %% Store the Ollama 'context' array here
    timestamp
}).
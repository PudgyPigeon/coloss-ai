# Don Erleone — Architecture Diagrams

## Current Architecture (as implemented)

```mermaid
graph TD
    subgraph External
        USER["curl / Frontend"]
    end

    subgraph "don_erleone (top supervisor)"
        subgraph "The Front"
            COWBOY["the_front (gen_server)"]
            HANDLER["openai_handler"]
            HEALTH["health_handler"]
        end

        subgraph "Consigliere Pool (poolboy, 5+10)"
            CW1["consigliere_worker"]
            CW2["consigliere_worker"]
            CWN["consigliere_worker ..."]
        end

        subgraph "Underboss (supervisor)"
            subgraph "Caporegime Pool (poolboy, 3+5)"
                CAP1["caporegime_worker"]
                CAP2["caporegime_worker"]
                CAPN["caporegime_worker ..."]
            end
        end

        MNESIA["mission_store (mnesia)"]
    end

    subgraph "Ollama Backend"
        BIG["Large Model (qwen3.5:9b)"]
        SMALL["Small Model (qwen2.5:1.5b)"]
    end

    USER -->|"POST /v1/chat/completions"| COWBOY
    COWBOY --> HANDLER
    HANDLER -->|"poolboy:transaction"| CW1
    CW1 -->|"HTTP POST"| BIG
    BIG -->|"JSON response"| CW1
    CW1 -->|"delegate_required=false"| MNESIA
    CW1 -->|"reply to cowboy"| HANDLER
    HANDLER -->|"200 JSON"| USER

    CW1 -->|"delegate_required=true"| MNESIA
    CW1 -->|"underboss:dispatch_mission"| CAP1
    CAP1 -->|"HTTP POST"| SMALL
    SMALL -->|"JSON response"| CAP1
    CAP1 -->|"complete/fail mission"| MNESIA

    style BIG fill:#e74c3c,color:#fff
    style SMALL fill:#3498db,color:#fff
    style MNESIA fill:#2ecc71,color:#fff
    style COWBOY fill:#9b59b6,color:#fff
```

### Flow Summary

1. **Request arrives** at `/v1/chat/completions` → `openai_handler`
2. **Consigliere pool** grabs a worker → calls large Ollama model
3. Large model returns JSON with `delegate_required: true/false`
4. **If false**: Direct response to user, mission logged to mnesia
5. **If true**: Response sent to user immediately, then `underboss:dispatch_mission/1` fires async
6. **Caporegime pool** grabs a worker → calls small Ollama model with intent-specific prompt
7. Result written back to mnesia (`complete_mission` or `fail_mission`)

---

## Future Architecture (where this should go)

```mermaid
graph TD
    subgraph External
        USER["curl / Frontend / OpenWebUI"]
        MCP_EXT["External MCP Servers"]
        WEBHOOKS["Webhooks / Events"]
    end

    subgraph "don_erleone (top supervisor)"
        subgraph "The Front"
            COWBOY["the_front (gen_server)"]
            HANDLER["openai_handler"]
            SSE["SSE streaming handler"]
            HEALTH["health + metrics handler"]
            WS["WebSocket handler"]
        end

        subgraph "Consigliere Pool (poolboy)"
            CW["consigliere_workers"]
        end

        subgraph "Underboss (supervisor)"
            DISPATCH["dispatch + routing logic"]
            subgraph "Caporegime Pool (poolboy)"
                CAP["caporegime_workers"]
            end
            subgraph "Fan-out Supervisor (simple_one_for_one)"
                LT1["mission_crew (supervisor)"]
                LT2["mission_crew (supervisor)"]
            end
        end

        subgraph "MCP Client Registry"
            MCP_REG["mcp_registry (gen_server)"]
            MCP_K8S["k8s_mcp_client"]
            MCP_NIX["nix_mcp_client"]
            MCP_GIT["git_mcp_client"]
        end

        subgraph "Persistence"
            MNESIA["mission_store (mnesia disc_copies)"]
            CONTEXT["context_store (conversation history)"]
        end

        subgraph "Observability"
            METRICS["prometheus_metrics"]
            TRACES["opentelemetry spans"]
        end
    end

    subgraph "Ollama Backend"
        BIG["Large Model (reasoning)"]
        MED["Medium Model (tasks)"]
        SMALL["Small Model (extraction)"]
    end

    USER -->|"POST + SSE"| COWBOY
    WEBHOOKS -->|"async events"| WS
    COWBOY --> HANDLER
    COWBOY --> SSE
    HANDLER --> CW
    CW --> BIG
    CW -->|"simple task"| CAP
    CW -->|"complex multi-step"| LT1
    CAP --> MED
    LT1 -->|"step 1: generate"| MED
    LT1 -->|"step 2: validate"| MCP_K8S
    LT1 -->|"step 3: apply"| MCP_K8S
    MCP_REG --> MCP_K8S
    MCP_REG --> MCP_NIX
    MCP_REG --> MCP_GIT
    MCP_K8S --> MCP_EXT
    CAP --> MNESIA
    LT1 --> MNESIA
    CW --> CONTEXT

    style BIG fill:#e74c3c,color:#fff
    style MED fill:#e67e22,color:#fff
    style SMALL fill:#3498db,color:#fff
    style MNESIA fill:#2ecc71,color:#fff
    style CONTEXT fill:#2ecc71,color:#fff
    style MCP_REG fill:#f39c12,color:#fff
```

### Evolution Roadmap

| Phase | What | Why |
|-------|------|-----|
| **Now** | Two pools (consigliere + caporegime), fire-and-forget delegation | Simple, working, debuggable |
| **Next** | MCP client registry — gen_server that holds connections to k8s, nix, git MCP servers | Caporegime workers can call real tools, not just Ollama |
| **Next** | `disc_copies` for mnesia + conversation context store | Durability across restarts, multi-turn memory |
| **Next** | SSE streaming from Ollama through to the frontend | Real-time UX instead of blocking 30s calls |
| **Later** | Fan-out supervisor for complex multi-step missions (bring back lieutenant pattern) | k8s_deploy = generate manifest → validate → apply → verify |
| **Later** | Prometheus metrics + OpenTelemetry tracing | Observe latency per model, pool saturation, mission success rates |
| **Later** | WebSocket handler for async mission status updates | Frontend can poll/subscribe to mission completion |

### Key Principle

> Start with flat pools, promote to supervision trees when a **specific mission type** proves it needs multi-step orchestration. The archived lieutenant/recruiter/associate code in `src_archived/` is your template for that promotion.

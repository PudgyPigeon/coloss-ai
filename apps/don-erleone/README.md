```
don_erleone (Top-Level Supervisor | Strategy: one_for_one)
 │
 ├── the_front (Cowboy HTTP/SSE Ingress Worker)
 │    └── Purpose: Handles incoming API requests and holds streaming connections.
 │
 └── the_commission (Core Sub-Supervisor | Strategy: rest_for_one)
      │    └── Purpose: Enforces shared fate between reasoning and execution.
      │
      ├── underboss (Execution Supervisor | Starts First)
      │    │
      │    └── caporegime_pool (Poolboy Manager)
      │         └── Purpose: Workers that execute Nix/K8s tool calls via the small LLM.
      │
      └── consigliere_pool (Reasoning Poolboy Manager | Starts Second)
           │
           └── Purpose: Workers that hold the system prompt and route intents via the large LLM.
```
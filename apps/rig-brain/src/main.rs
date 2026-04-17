mod mcp;
mod api;

use mcp::{MockMcpClient, K8sTool, SubagentTool};
use rig::providers::openai;
use rig::client::{ProviderClient, CompletionClient};
use std::sync::Arc;
use api::ax_state::AppState;

#[derive(Debug)]
struct AppConfig {
    enable_subagents: bool,
    brain_model: String,
    subagent_model: String,
    port: String,
}

impl AppConfig {
    fn from_env() -> Self {
        Self {
            enable_subagents: std::env::var("ENABLE_SUBAGENTS").map(|v| v == "true").unwrap_or(false),
            brain_model: std::env::var("BRAIN_MODEL").unwrap_or_else(|_| "gpt-4o".to_string()),
            subagent_model: std::env::var("SUBAGENT_MODEL").unwrap_or_else(|_| "gpt-4o-mini".to_string()),
            port: std::env::var("PORT").unwrap_or_else(|_| "3000".to_string()),
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    // 0. Initialize Environment and Logging
    dotenv::dotenv().ok();
    tracing_subscriber::fmt::init();

    let config = AppConfig::from_env();
    tracing::info!("Starting Rig Brain with config: {:?}", config);

    // 1. Initialize the MCP Client (Mock for now)
    let mcp_client = Arc::new(MockMcpClient);

    // 2. Initialize the completion provider
    // Note: To use Ollama or other local proxies, set OPENAI_API_BASE in .env
    let client = openai::Client::from_env();

    // 3. Define Tools
    let list_pods = K8sTool {
        name: "ListPods".to_string(),
        description: "List all pods in a given namespace".to_string(),
        client: mcp_client.clone(),
    };

    let get_pod = K8sTool {
        name: "GetPod".to_string(),
        description: "Get detailed JSON information about a specific pod".to_string(),
        client: mcp_client.clone(),
    };

    // 4. Build the Agentic Hierarchy
    let brain = if config.enable_subagents {
        tracing::info!("Configuring Brain in DELEGATION mode");
        
        let k8s_subagent = client
            .agent(&config.subagent_model)
            .preamble("You are a Kubernetes Specialist. Use tools to list and get pods.")
            .tool(list_pods)
            .tool(get_pod)
            .build();
        
        let k8s_subagent_tool = SubagentTool {
            name: "KubernetesAssistant".to_string(),
            description: "Delegates all Kubernetes-related tasks to this specialized assistant.".to_string(),
            agent: k8s_subagent,
        };

        client
            .agent(&config.brain_model)
            .preamble("You are the Central Brain. For any Kubernetes queries, delegate to simple subagents.")
            .tool(k8s_subagent_tool)
            .build()
    } else {
        tracing::info!("Configuring Brain in DIRECT mode");
        
        client
            .agent(&config.brain_model)
            .preamble("You are a Kubernetes Cloud Architect. Use tools directly.")
            .tool(list_pods)
            .tool(get_pod)
            .build()
    };

    let shared_state = Arc::new(AppState {
        agent: Arc::new(brain),
        sessions: dashmap::DashMap::new(),
    });

    // 5. Start the Server
    let app = api::create_router(shared_state);
    
    let addr = format!("0.0.0.0:{}", config.port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    
    tracing::info!("Rig Brain API listening on http://{}", addr);
    axum::serve(listener, app).await?;

    Ok(())
}


mod mcp;

use mcp::{MockMcpClient, K8sTool};
use rig::providers::openai;
use rig::completion::Prompt;
use std::sync::Arc;

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    // 0. Initialize Logging
    tracing_subscriber::fmt::init();

    // 1. Initialize the Mock MCP Client
    // In the future, this will be an HttpClient(url: "http://localhost:30090/mcp")
    let mcp_client = Arc::new(MockMcpClient);

    // 2. Wrap our Haskell tools into Rig tools
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

    // 3. Initialize the completion provider
    // Using OpenAI scaffold, but point to Ollama locally when ready
    let client = openai::Client::from_env();

    // 4. Build the Agentic Brain with Tools
    let brain = client
        .agent("gpt-4o")
        .preamble("You are a Kubernetes Cloud Architect. Use tools to inspect the cluster.")
        .tool(list_pods)
        .tool(get_pod)
        .build();

    // 5. Test Prompt (Simulating a local interaction)
    println!("--- Rig Brain: Offline Local Dev Mode ---");
    let query = "Are there any pods running in the 'kube-system' namespace?";
    println!("Query: {}", query);

    // Note: Since we don't have a real LLM running right now, 
    // we use tracing to show that the code path works.
    let response = brain.prompt(query).await?;
    println!("Brain Response: {}", response);

    Ok(())
}
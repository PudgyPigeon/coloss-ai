use serde::{Deserialize, Serialize};
use rig::tool::Tool;
use std::sync::Arc;
use async_trait::async_trait;

// --- MCP Protocol Types ---

#[derive(Serialize, Deserialize, Debug)]
pub struct McpRequest {
    pub jsonrpc: String,
    pub method: String,
    pub params: McpParams,
    pub id: u32,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct McpParams {
    pub name: String,
    pub arguments: serde_json::Value,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct McpResponse {
    pub jsonrpc: String,
    pub result: serde_json::Value,
    pub id: u32,
}

// --- K8s Tool Arguments (Matching Haskell Types.hs) ---

#[derive(Deserialize, Serialize, Debug)]
pub struct ListArgs {
    pub namespace: String,
}

#[derive(Deserialize, Serialize, Debug)]
pub struct GetArgs {
    pub namespace: String,
    pub name: String,
}

// --- Client Abstraction ---

#[async_trait]
pub trait McpClient: Send + Sync {
    async fn call_tool(&self, name: &str, args: serde_json::Value) -> Result<serde_json::Value, anyhow::Error>;
}

// --- Mock Implementation ---

pub struct MockMcpClient;

#[async_trait]
impl McpClient for MockMcpClient {
    async fn call_tool(&self, name: &str, args: serde_json::Value) -> Result<serde_json::Value, anyhow::Error> {
        tracing::info!("Mocking MCP call: {} with args: {}", name, args);
        
        match name {
            "ListPods" => {
                let ns = args.get("namespace").and_then(|v| v.as_str()).unwrap_or("default");
                Ok(serde_json::json!({
                    "output": format!("NAME                     STATUS    AGE\nmock-pod-1-{ns}          Running   1h\nmock-pod-2-{ns}          Pending   2m")
                }))
            },
            "GetPod" => {
                let name = args.get("name").and_then(|v| v.as_str()).unwrap_or("unknown");
                Ok(serde_json::json!({
                    "kind": "Pod",
                    "metadata": { "name": name, "namespace": "default" },
                    "status": { "phase": "Running" }
                }))
            },
            _ => Err(anyhow::anyhow!("Tool {} not implemented in MockClient", name)),
        }
    }
}

// --- Rig Tool Bridges ---

pub struct K8sTool {
    pub name: String,
    pub description: String,
    pub client: Arc<dyn McpClient>,
}

#[async_trait]
impl Tool for K8sTool {
    type Args = serde_json::Value;
    type Output = serde_json::Value;
    type Error = anyhow::Error;

    fn definition(&self, _args: &Self::Args) -> rig::tool::ToolDefinition {
        rig::tool::ToolDefinition {
            name: self.name.clone(),
            description: self.description.clone(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "namespace": {
                        "type": "string",
                        "description": "The Kubernetes namespace"
                    },
                    "name": {
                        "type": "string",
                        "description": "The resource name (optional for List commands)"
                    }
                }
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        self.client.call_tool(&self.name, args).await
    }
}

use serde::{Deserialize, Serialize};
use rig::tool::Tool;
use rig::completion::Prompt;
use std::sync::Arc;
use async_trait::async_trait;

// --- MCP Protocol Types (Reserved for future real integration) ---

#[allow(dead_code)]
#[derive(Serialize, Deserialize, Debug)]
pub struct McpRequest {
    pub jsonrpc: String,
    pub method: String,
    pub params: McpParams,
    pub id: u32,
}

#[allow(dead_code)]
#[derive(Serialize, Deserialize, Debug)]
pub struct McpParams {
    pub name: String,
    pub arguments: serde_json::Value,
}

#[allow(dead_code)]
#[derive(Serialize, Deserialize, Debug)]
pub struct McpResponse {
    pub jsonrpc: String,
    pub result: serde_json::Value,
    pub id: u32,
}

// --- K8s Tool Arguments (Matching Haskell Types.hs) ---

#[allow(dead_code)]
#[derive(Deserialize, Serialize, Debug)]
pub struct ListArgs {
    pub namespace: String,
}

#[allow(dead_code)]
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

// Support for dyn McpClient
impl dyn McpClient {
    // If we need specific dyn methods, add them here
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

impl Tool for K8sTool {
    const NAME: &'static str = "k8s_tool";

    type Args = serde_json::Value;
    type Output = serde_json::Value;
    type Error = McpError;

    async fn definition(&self, _args: String) -> rig::completion::ToolDefinition {
        rig::completion::ToolDefinition {
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
            .map_err(|e| McpError(e.to_string()))
    }
}

#[derive(Debug)]
pub struct McpError(String);

impl std::fmt::Display for McpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::error::Error for McpError {}

// --- Subagent Support ---

#[derive(Deserialize, Serialize, Debug)]
pub struct SubagentArgs {
    pub query: String,
}

pub struct SubagentTool<M: rig::completion::CompletionModel> {
    pub name: String,
    pub description: String,
    pub agent: rig::agent::Agent<M>,
}

impl<M: rig::completion::CompletionModel + 'static> Tool for SubagentTool<M> {
    const NAME: &'static str = "subagent_tool";

    type Args = SubagentArgs;
    type Output = String;
    type Error = McpError;

    async fn definition(&self, _args: String) -> rig::completion::ToolDefinition {
        rig::completion::ToolDefinition {
            name: self.name.clone(),
            description: self.description.clone(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "The natural language query or task for the subagent to perform"
                    }
                },
                "required": ["query"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        tracing::info!("Delegating to subagent: {} with query: {}", self.name, args.query);
        self.agent.prompt(&args.query).await
            .map_err(|e| McpError(e.to_string()))
    }
}

// --- Tests ---

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_mock_mcp_list_pods() {
        let client = MockMcpClient;
        let args = serde_json::json!({ "namespace": "test-ns" });
        let result = client.call_tool("ListPods", args).await.unwrap();
        
        let output = result.get("output").and_then(|v| v.as_str()).unwrap();
        assert!(output.contains("mock-pod-1-test-ns"));
    }

    #[tokio::test]
    async fn test_mock_mcp_get_pod() {
        let client = MockMcpClient;
        let args = serde_json::json!({ "name": "pod-a" });
        let result = client.call_tool("GetPod", args).await.unwrap();
        
        assert_eq!(result.get("kind").and_then(|v| v.as_str()).unwrap(), "Pod");
        let name = result.get("metadata").and_then(|m| m.get("name")).and_then(|v| v.as_str()).unwrap();
        assert_eq!(name, "pod-a");
    }

    #[tokio::test]
    async fn test_mock_mcp_invalid_tool() {
        let client = MockMcpClient;
        let args = serde_json::json!({});
        let result = client.call_tool("InvalidTool", args).await;
        assert!(result.is_err());
    }
}

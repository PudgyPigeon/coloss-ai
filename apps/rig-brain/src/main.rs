use rig::providers::openai;
use rig::completion::Prompt;
use rig::client::ProviderClient;
use rig::client::CompletionClient;

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    // 1. Initialize the client 
    // Point this to your Ollama service in the 'infra' namespace later
    let client = openai::Client::from_env();

    // 2. Build the Agentic Brain
    let brain = client
        .agent("gpt-4o") // Or your local qwen2.5-coder
        .preamble("You are a high-performance infrastructure orchestrator.")
        .build();

    // 3. Simple test prompt
    let response = brain.prompt("Status check on the market data feed.").await?;

    println!("Brain Response: {}", response);

    Ok(())
}
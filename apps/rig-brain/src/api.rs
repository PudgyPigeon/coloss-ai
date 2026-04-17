use self::ax_state::AppState;
use axum::{
    extract::State,
    response::sse::{Event, Sse},
    routing::{get, post},
    Json, Router,
    response::IntoResponse,
};
use async_openai::types::{
    ChatChoice, ChatCompletionResponseMessage, CreateChatCompletionRequest,
    CreateChatCompletionResponse, Role, 
    CreateChatCompletionStreamResponse,
};
use rig::completion::{Message, Prompt, AssistantContent};
use rig::streaming::StreamingPrompt;
use rig::OneOrMany;
use std::sync::Arc;
use tower_http::cors::CorsLayer;
use futures::stream::StreamExt;

pub mod ax_state {
    use std::sync::Arc;
    use rig::agent::Agent;
    use rig::completion::CompletionModel;
    use dashmap::DashMap;
    use rig::completion::Message;

    pub struct AppState<M: CompletionModel> {
        pub agent: Arc<Agent<M>>,
        pub sessions: DashMap<String, Vec<Message>>,
    }
}

pub fn create_router<M: rig::completion::CompletionModel + 'static>(state: Arc<AppState<M>>) -> Router 
where <M as rig::completion::CompletionModel>::StreamingResponse: std::fmt::Debug
{
    Router::new()
        .route("/v1/chat/completions", post(chat_completions::<M>))
        .route("/v1/models", get(list_models))
        .layer(CorsLayer::permissive())
        .with_state(state)
}

async fn list_models() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "object": "list",
        "data": [
            {
                "id": "rig-brain",
                "object": "model",
                "created": 1677610602,
                "owned_by": "rig"
            }
        ]
    }))
}

async fn chat_completions<M: rig::completion::CompletionModel + 'static>(
    State(state): State<Arc<AppState<M>>>,
    Json(request): Json<CreateChatCompletionRequest>,
) -> Result<axum::response::Response, (axum::http::StatusCode, String)> 
where <M as rig::completion::CompletionModel>::StreamingResponse: std::fmt::Debug
{
    tracing::info!("Received chat completion request (stream={})", request.stream.unwrap_or(false));

    // 1. Determine session/history
    let session_id = "default-session".to_string();
    let mut history_entry = state.sessions.entry(session_id.clone()).or_insert(vec![]);

    // 2. Extract current query
    let query = request.messages.last()
        .and_then(|m| match m {
            async_openai::types::ChatCompletionRequestMessage::User(u) => {
                match &u.content {
                    async_openai::types::ChatCompletionRequestUserMessageContent::Text(t) => Some(t.clone()),
                    _ => None,
                }
            },
            _ => None,
        })
        .unwrap_or_else(|| "Hello".to_string());

    // 3. Handle Streaming
    if request.stream.unwrap_or(false) {
        let agent = state.agent.clone();
        
        // Start the stream
        let rig_stream = agent.stream_prompt(&query).await;

        // Convert the stream chunks into SSE events
        let event_stream = rig_stream.map(move |chunk| {
            match chunk {
                Ok(item) => {
                    // We use Debug fallback since we are in a generic context
                    let text = format!("{:?}", item);
                    
                    let response = CreateChatCompletionStreamResponse {
                        id: "rig-chat-stream".to_string(),
                        object: "chat.completion.chunk".to_string(),
                        created: chrono::Utc::now().timestamp() as u32,
                        model: "rig-brain".to_string(),
                        choices: vec![serde_json::from_value(serde_json::json!({
                            "index": 0,
                            "delta": {
                                "content": text
                            },
                            "finish_reason": null
                        })).unwrap()],
                        usage: None,
                        system_fingerprint: None,
                        service_tier: None,
                    };
                    Ok::<Event, std::io::Error>(Event::default().json_data(response).unwrap())
                },
                Err(e) => {
                    tracing::error!("Stream error: {}", e);
                    Ok::<Event, std::io::Error>(Event::default().data(format!("error: {}", e)))
                }
            }
        });

        Ok(Sse::new(event_stream).into_response())
    } else {
        // 4. Handle Non-Streaming
        let response_text = state.agent.prompt(&query).await
            .map_err(|e| (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

        // Update history with assistant response
        history_entry.push(Message::Assistant { 
            id: None,
            content: OneOrMany::one(AssistantContent::text(response_text.clone())) 
        });

        let response = CreateChatCompletionResponse {
            id: "rig-chat-res".to_string(),
            object: "chat.completion".to_string(),
            created: chrono::Utc::now().timestamp() as u32,
            model: "rig-brain".to_string(),
            choices: vec![ChatChoice {
                index: 0,
                message: ChatCompletionResponseMessage {
                    role: Role::Assistant,
                    content: Some(response_text),
                    tool_calls: None,
                    #[allow(deprecated)]
                    function_call: None,
                    refusal: None,
                },
                finish_reason: Some(async_openai::types::FinishReason::Stop),
                logprobs: None,
            }],
            usage: None,
            system_fingerprint: None,
            service_tier: None,
        };

        Ok(Json(response).into_response())
    }
}

#!/usr/bin/env bash

# Integration test script for Kubernetes MCP Protocol
# Ensure `just watch` or `just run` is executing in another terminal on port 30090 before running this.

echo "Starting SSE connection to capture server push events..."
curl -N -sSf http://localhost:30090/sse > sse-test.log 2>&1 &
SSE_PID=$!

# Wait briefly for SSE connection to establish and capture the <endpoint: /message> discovery payload
sleep 1

echo "Sending MCP 'initialize' JSON-RPC Request..."
curl -v -sSf -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}' \
  http://localhost:30090/message
echo ""

sleep 1

echo "Sending MCP 'tools/list' JSON-RPC Request..."
curl -v -sSf -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}' \
  http://localhost:30090/message
echo ""

sleep 1

# Kill the background SSE connection process
kill $SSE_PID

echo "=== SSE Stream Result ==="
cat sse-test.log
echo ""
echo "Done! If the JSON-RPC responses routed correctly into the SSE stream above, the integration succeeds!"

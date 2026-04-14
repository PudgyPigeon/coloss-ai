#!/usr/bin/env bash
set -e

echo "Building git-mcp locally..."
just build

echo "Starting git-mcp server..."
cabal run exe:git-mcp -- --port 10001 &
PID=$!
sleep 2

echo "Starting SSE listener in background..."
curl -s -N http://localhost:10001/sse > sse.log 2>&1 &
SSE_PID=$!
sleep 1

cleanup() {
    echo "Shutting down git-mcp server (PID $PID) and SSE (PID $SSE_PID)..."
    kill $PID
    kill $SSE_PID
}
trap cleanup EXIT

echo "=== Testing tools/list ==="
curl -X POST http://localhost:10001/message \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list",
    "params": {}
  }'
echo -e "\n"

echo "=== Testing git_status via tools/call ==="
curl -X POST http://localhost:10001/message \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "git_status",
      "arguments": {}
    }
  }'
echo -e "\n"

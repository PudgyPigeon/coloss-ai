#!/usr/bin/env bash
# test-mcp-integration.sh — MCP protocol integration test via stdio
#
# Usage: ./test-mcp-integration.sh
#
# This sends JSON-RPC messages to the kubernetes-mcp server over stdio
# and validates the responses.

set -euo pipefail

APP="cabal run kubernetes-mcp -- --transport stdio"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
info() { echo -e "${BLUE}→ $1${NC}"; }

# Send a JSON-RPC message and capture the response
send_message() {
    local msg="$1"
    echo "$msg"
}

info "Building kubernetes-mcp..."
cabal build kubernetes-mcp 2>/dev/null || { fail "Build failed"; }

info "Testing MCP initialize handshake..."
INIT_REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"0.1.0"}}}'
INIT_NOTIF='{"jsonrpc":"2.0","method":"notifications/initialized"}'
TOOLS_LIST='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

# Send init + notification + tools/list, capture all output
RESPONSE=$(printf '%s\n%s\n%s\n' "$INIT_REQ" "$INIT_NOTIF" "$TOOLS_LIST" | timeout 10 $APP 2>/dev/null || true)

# Check initialize response
if echo "$RESPONSE" | grep -q '"serverInfo"'; then
    pass "Initialize handshake succeeded"
else
    fail "Initialize handshake failed. Response: $RESPONSE"
fi

# Check tools/list response contains our tools
if echo "$RESPONSE" | grep -q '"list_pods"'; then
    pass "tools/list contains list_pods"
else
    fail "tools/list missing list_pods. Response: $RESPONSE"
fi

if echo "$RESPONSE" | grep -q '"get_pod"'; then
    pass "tools/list contains get_pod"
else
    fail "tools/list missing get_pod. Response: $RESPONSE"
fi

if echo "$RESPONSE" | grep -q '"list_namespaces"'; then
    pass "tools/list contains list_namespaces"
else
    fail "tools/list missing list_namespaces. Response: $RESPONSE"
fi

if echo "$RESPONSE" | grep -q '"get_pod_logs"'; then
    pass "tools/list contains get_pod_logs"
else
    fail "tools/list missing get_pod_logs. Response: $RESPONSE"
fi

echo ""
pass "All MCP integration tests passed!"

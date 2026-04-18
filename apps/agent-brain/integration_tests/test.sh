#!/usr/bin/env bash

# Exit on error, but allow pipe failures for custom handling
set -eo pipefail

# Configuration
API_URL="http://localhost:8080/user"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Helper function to check for jq
HAS_JQ=$(command -v jq >/dev/null 2>&1 && echo true || echo false)

echo -e "${BLUE}--- Testing Agent Brain API ---${NC}"

# 1. Test GET
echo -e "\n${GREEN}[GET /user]${NC}"
RESPONSE_GET=$(curl -s -w "\n%{http_code}" "$API_URL")
STATUS_GET=$(echo "$RESPONSE_GET" | tail -n1)
BODY_GET=$(echo "$RESPONSE_GET" | head -n -1)

if [ "$STATUS_GET" -eq 200 ]; then
    echo -e "Status: ${GREEN}$STATUS_GET${NC}"
    [[ "$HAS_JQ" == "true" ]] && echo "$BODY_GET" | jq . || echo "$BODY_GET"
else
    echo -e "Status: ${RED}$STATUS_GET${NC}"
    echo "$BODY_GET"
fi

# 2. Test POST
echo -e "\n${GREEN}[POST /user]${NC}"
PAYLOAD='{"userId": 99, "userName": "Tommy-Nix-Agent"}'
RESPONSE_POST=$(curl -s -w "\n%{http_code}" -X POST "$API_URL" \
     -H "Content-Type: application/json" \
     -d "$PAYLOAD")
STATUS_POST=$(echo "$RESPONSE_POST" | tail -n1)
BODY_POST=$(echo "$RESPONSE_POST" | head -n -1)

if [ "$STATUS_POST" -eq 200 ] || [ "$STATUS_POST" -eq 201 ]; then
    echo -e "Status: ${GREEN}$STATUS_POST${NC}"
    [[ "$HAS_JQ" == "true" ]] && echo "$BODY_POST" | jq . || echo "$BODY_POST"
else
    echo -e "Status: ${RED}$STATUS_POST${NC}"
    echo "$BODY_POST"
fi

echo -e "\n${BLUE}--- Tests Complete ---${NC}"
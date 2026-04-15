import requests
from datetime import datetime
from pydantic import Field

class Tools:
    def __init__(self):
        pass

    def check_infra_health(
        self, 
        endpoint: str = Field(
            "health", 
            description="The infra endpoint to check. Options: 'health', 'status', 'env'."
        )
    ) -> str:
        """
        Check the physical health of the Haskell MCP server and infrastructure.
        Use this to verify the SRE sidecar is running when the native MCP connection fails.
        """
        port = 8081
        # Port 8081 is the dedicated health/metrics server
        url = f"http://kubernetes-mcp.kubernetes-mcp.svc.cluster.local:{port}/{endpoint.lstrip('/')}"
        
        try:
            response = requests.get(url, timeout=5)
            response.raise_for_status()
            return f"Infrastructure {endpoint.upper()} Check: {response.text}"
        except Exception as e:
            return f"SRE ALERT: Could not reach health server on port 8081. Error: {str(e)}"

    def get_current_time(self) -> str:
        """Get the current local time for log timestamping."""
        return datetime.now().strftime("%A, %B %d, %Y, %I:%M:%S %p")

    def calculator(self, equation: str = Field(..., description="The math equation to calculate.")) -> str:
        """Perform simple math for resource calculations."""
        try:
            # Safer eval with restricted globals
            result = eval(equation, {"__builtins__": None}, {})
            return f"{equation} = {result}"
        except Exception as e:
            return f"Invalid calculation: {str(e)}"

# import os
# import requests
# from datetime import datetime
# from pydantic import BaseModel, Field

# class Tools:
#     def __init__(self):
#         pass

#     def query_mcp_api(self, endpoint: str = "mcp", method: str = "initialize") -> str:
#         """
#         Query the Haskell MCP server. 
#         Methods: 'initialize' to start, 'tools/list' to see tools, 'resources/list' for resources.
#         """
#         infra_endpoints = ["health", "status", "env"]
#         port = 8081 if endpoint in infra_endpoints else 8080
#         url = f"http://kubernetes-mcp.kubernetes-mcp.svc.cluster.local:{port}/{endpoint.lstrip('/')}"

#         headers = {
#             "MCP-Protocol-Version": "2025-06-18",
#             "Content-Type": "application/json",
#         }

#         try:
#             if port == 8080:
#                 # If the LLM wants to list namespaces, we format it as a JSON-RPC call
#                 # Most MCP servers use 'tools/call' or specific list methods
#                 m_name = "initialize" if method == "initialize" else method
                
#                 payload = {
#                     "jsonrpc": "2.0",
#                     "id": 1,
#                     "method": m_name,
#                     "params": {
#                         "protocolVersion": "2025-06-18",
#                         "capabilities": {},
#                         "clientInfo": {"name": "open-webui-tool", "version": "1.0.0"}
#                     }
#                 }
                
#                 # If we are calling a specific tool like list_namespaces
#                 if method == "list_namespaces":
#                     payload["method"] = "tools/call"
#                     payload["params"] = {"name": "list_namespaces", "arguments": {}}

#                 response = requests.post(url, headers=headers, json=payload, timeout=5)
#             else:
#                 response = requests.get(url, headers=headers, timeout=5)

#             response.raise_for_status()
#             return response.text
#         except Exception as e:
#             return f"Error: {str(e)}"
    
#     def get_current_time(self) -> str:
#         """Get the current local time and date for infrastructure logging."""
#         return datetime.now().strftime("Current Date and Time = %A, %B %d, %Y, %I:%M:%S %p")

#     def calculator(self, equation: str = Field(..., description="The math equation to calculate.")) -> str:
#         """Evaluate mathematical expressions safely."""
#         try:
#             # Use a restricted set of globals for safety
#             result = eval(equation, {"__builtins__": None}, {})
#             return f"{equation} = {result}"
#         except Exception as e:
#             return f"Invalid equation: {str(e)}"

#     def get_user_info(self, __user__: dict = {}) -> str:
#         """Access the current session's user metadata."""
#         name = __user__.get("name", "Unknown")
#         user_id = __user__.get("id", "N/A")
#         return f"User Context: {name} (ID: {user_id})"
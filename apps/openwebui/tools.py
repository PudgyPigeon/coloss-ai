import os
import requests
from datetime import datetime
from pydantic import BaseModel, Field

class Tools:
    def __init__(self):
        pass

    def query_mcp_api(
        self,
        endpoint: str = Field(
            "status", 
            description="The API endpoint to query. Use 'status' for health checks or 'env' for environment details."
        ),
    ) -> str:
        """
        Query the local Haskell MCP infrastructure server. 
        Use this tool to check if the Kubernetes agent is online or to verify the current deployment environment.
        """
        # Note: In Docker-based Open WebUI, 'host.docker.internal' reaches the WSL2/Nix host.
        # We check both to be safe.
        urls = [
            f"http://172.23.204.227:30090/{endpoint.lstrip('/')}",
            f"http://host.docker.internal:30090/{endpoint.lstrip('/')}"
        ]
        
        last_error = ""
        for url in urls:
            try:
                response = requests.get(url, timeout=3)
                response.raise_for_status()
                return f"MCP {endpoint.capitalize()} Response: {response.text}"
            except requests.exceptions.RequestException as e:
                last_error = str(e)
                continue
        
        return f"Error: Could not connect to Haskell MCP at 30090. (Last error: {last_error})"

    def get_current_time(self) -> str:
        """
        Get the current local time and date. Useful for timestamping infrastructure logs.
        """
        now = datetime.now()
        return now.strftime("Current Date and Time = %A, %B %d, %Y, %I:%M:%S %p")

    def calculator(
        self,
        equation: str = Field(..., description="The mathematical equation to calculate.")
    ) -> str:
        """
        Evaluate mathematical expressions.
        """
        try:
            # Note: restricted globals for a slightly safer eval
            result = eval(equation, {"__builtins__": None}, {})
            return f"{equation} = {result}"
        except Exception as e:
            return f"Invalid equation: {str(e)}"

    def get_user_info(self, __user__: dict = {}) -> str:
        """
        Access the current session's user metadata.
        """
        name = __user__.get("name", "Unknown")
        user_id = __user__.get("id", "N/A")
        return f"User Context: {name} (ID: {user_id})"
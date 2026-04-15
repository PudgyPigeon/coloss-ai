# Integrating MCP servers into Open Web UI

- As of right now the workflow is as follows:
- Go to Admin Panel
- > Settings tab in the top right
- > Integrations in the list on the mid-top left
- > Manage Tool Servers
- > Add a new connection with the "+" or edit a current connection with the Cog gear
- > Give it a name and unique ID
- > Put the URL such as `http://kubernetes-mcp.kubernetes-mcp.svc.cluster.local:8080/mcp`
- > Set Auth to None by default unless token is added
- > In Advanced, add 'Headers' JSON in the textbox
- > Double check with Server logs in ArgoCD or kubectl to confirm handshake and initialize work

```
{
  "MCP-Protocol-Version": "2025-06-18",
  "Content-Type": "application/json",
  "Accept": "application/json"
}
```


```
minikube image rm docker.io/library/kubernetes-mcp:latest
```
# About
Hermetic, deterministic, one-click Kubernetes cluster with Ollama + OpenWebUI + ArgoCD.

GPU integration may not work with your system - it depends on if your system mirrors the Nix settings 
as declared here: https://github.com/PudgyPigeon/nix-base

# Nix Commands to Run

```
# To enter shell
nix develop 

# To format (Uses Alejandra)
nix fmt .
```

# Gotchas with deployment
### Gitea localhost not updating
If the Nix shell isnt propagating changes to Gitea, just exit the shell, re-enter and run the sync command again

### Argo not updating
Sometimes you need to run the `up` command or just wait for ArgoCD to reconcile itself for around 5 minutes.

OR
`kubectl exec -n argocd -it deploy/argocd-repo-server -- rm -rf /tmp/_argocd-repo`
OR
`argocd cluster add $(kubectl config current-context) --name in-cluster `

Even if it fails it'll add some roles.

### Ollama Helm Chart running
For now no script. You need to run the following on startup:
```
kubectl port-forward svc/ollama-internal 11434:11434 -n ollama > /dev/null 2>&1 &
<!-- kubectl exec -it deploy/ollama-internal -n ollama -- ollama pull llama3.2:3b -->
kubectl exec -it deploy/ollama-internal -n ollama -- ollama pull llama3:latest
kubectl port-forward -n open-webui svc/open-webui 9000:8080 > /dev/null 2>&1 &

# Test openwebui to ollama kubectl exec -it -n open-webui deploy/open-webui -- curl http://ollama-internal.ollama.svc.cluster.local:11434/api/tags
```


# Resources

## FluxCD + Capacitor
https://gimlet.io/capacitor-next/
https://oneuptime.com/blog/post/2026-03-06-use-capacitor-dashboard-flux-cd/view
https://fluxcd.io/blog/2024/02/introducing-capacitor/
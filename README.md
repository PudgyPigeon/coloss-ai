# Nix Commands to Run

```
# To enter shell
nix develop 

# To format (Uses Alejandra)
nix fmt .
```

## Gotchas with deployment
When you run 'up' or 'argocd-up' in `nix develop` shell, you may need to run it twice to account for CRDs taking time to provision.
So if it fails once, just run the command again after a few seconds and it should be fine.

### Gitea localhost not updating
Maybe the nix cache is stale. You can fix it by running the following:
```
rm -rf .nix-cache # once you've exited the nix shell
git add .
# Then 
nix develop # flag optional -> --refresh
# OR
nix build .#renderedManifests-sandbox --rebuild
```

# Argo not updating
Sometimes you need to run the `up` command or just wait for ArgoCD to reconcile itself for around 5 minutes.

OR
`kubectl exec -n argocd -it deploy/argocd-repo-server -- rm -rf /tmp/_argocd-repo`
OR
`argocd cluster add $(kubectl config current-context) --name in-cluster `

Even if it fails it'll add some roles.

# Ollama Helm Chart running
For now no script. You might need to run the following on startup:
`kubectl port-forward svc/ollama-internal 11434:11434 -n ollama > /dev/null 2>&1 &`
`kubectl exec -it deploy/ollama-agent -n ollama -- ollama pull llama3.2:3b`
`kubectl port-forward svc/open-webui 8080:8080 -n ollama > /dev/null 2>&1 &`
# Resources

## FluxCD + Capacitor
https://gimlet.io/capacitor-next/
https://oneuptime.com/blog/post/2026-03-06-use-capacitor-dashboard-flux-cd/view
https://fluxcd.io/blog/2024/02/introducing-capacitor/
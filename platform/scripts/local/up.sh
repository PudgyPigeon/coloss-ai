#!/usr/bin/env bash
infra-up      # 1. Start Minikube & core infra
load-images   # 2. Build and load custom images (don-erleone, etc.) into Minikube
argocd-up     # 3. Spin up ArgoCD
sync-helm     # 4. Push manifests to Gitea (ArgoCD will now find cached images)
expose        # 5. Open tunnels and dashboards
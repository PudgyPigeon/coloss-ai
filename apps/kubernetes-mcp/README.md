# Haskell Kubernetes MCP Server

A robust, type-safe MCP (Model Context Protocol) server for Kubernetes, implemented in Haskell. This server allows LLMs to interact with your Kubernetes clusters securely.

## 🛠️ Development

This project uses `nix` and `just` for a reproducible development environment.

### Prerequisites
- [Nix](https://nixos.org/download.html) with Flakes enabled.
- [direnv](https://direnv.net/) (optional but recommended).

### Commands
Run `just` to see all available recipes:

```bash
# Watch for changes and run REPL
just watch

# Build the project
just build

# Run tests
just test

# Build the OCI image via Nix
just load-image
```

## 🚀 Deployment (Helm)

A simplified Helm chart is provided for easy deployment to your Kubernetes cluster.

### Path
`charts/kubernetes-mcp`

### Usage

**1. Preview Manifests:**
```bash
helm template charts/kubernetes-mcp
```

**2. Install Chart:**
```bash
helm install kubernetes-mcp ./charts/kubernetes-mcp \
  --namespace mcp \
  --create-namespace
```

### Configuration
Key values in `values.yaml`:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Docker image repository | `kubernetes-mcp` |
| `config.port` | MCP HTTP transport port | `30090` |
| `config.healthPort` | Health probe port | `30091` |
| `config.env` | Environment (prod/staging/dev) | `dev` |
| `rbac.create` | Create RBAC resources | `true` |

## 🧩 Features
- **Type-safe K8s interaction**: Leverages Haskell's type system for reliable API calls.
- **MCP Compliance**: Full support for the Model Context Protocol.
- **RBAC Ready**: Includes necessary ClusterRoles for listing and getting cluster resources.
- **Lean Footprint**: Optimized OCI images built with `nix2container`.
import Config

# 1. Handle node naming
if config_env() == :prod do
  pod_ip = System.get_env("POD_IP" || "127.0.0.1")
  node_name = System.get_env("NODE_NAME") || "wire"

  System.put_env("RELEASE_NODE", "#{node_name}@#{pod_ip}")
  System.put_env("RELEASE_COOKIE", "agentic_brain_secret")
end

# 2. Configure libcluster
if System.get_env("KUBERNETES_SERVICE_HOST") do
  config :libcluster,
    topologies: [
      k8s_distro: [
        strategy: Cluster.Strategy.Kubernetes,
        config: [
          mode: :ip,
          kubernetes_node_basename: "don_erleone",
          kubernetes_selector: "app=don-erleone",
          kubernetes_namespace: SYSTEM.get_env("NAMESPACE" || "don-erleone")
        ]
      ]
    ]
  else
    config :libcluster, topologies: []
end

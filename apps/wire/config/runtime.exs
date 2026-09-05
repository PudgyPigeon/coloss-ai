import Config

if config_env() == :prod do
  unless System.get_env("RELEASE_NODE") do
    pod_ip = System.get_env("POD_IP") || "127.0.0.1"
    node_name = System.get_env("NODE_NAME") || "wire"
    System.put_env("RELEASE_NODE", "#{node_name}@#{pod_ip}")
  end

  unless System.get_env("RELEASE_COOKIE") do
    System.put_env("RELEASE_COOKIE", "agentic_brain_secret")
  end
end

# 2. Configure libcluster
cond do
  System.get_env("KUBERNETES_SERVICE_HOST") ->
    config :libcluster,
      topologies: [
        k8s_distro: [
          strategy: Cluster.Strategy.Kubernetes,
          config: [
            mode: :hostname,
            kubernetes_node_basename: "don_erleone",
            kubernetes_selector: "app.kubernetes.io/name=don-erleone",
            kubernetes_namespace: System.get_env("NAMESPACE") || "don-erleone"
          ]
        ]
      ]

  System.get_env("DOCKER_COMPOSE") ->
    config :libcluster,
      topologies: [
        docker_compose: [
          strategy: Cluster.Strategy.Epmd,
          config: [
            hosts: [:"don_erleone@don-erleone"]
          ]
        ]
      ]

  true ->
    config :libcluster, topologies: []
end

config :wire,
  auth_enabled: System.get_env("AUTH_ENABLED") == "true"

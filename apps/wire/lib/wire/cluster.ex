defmodule Wire.Cluster do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    topologies = Application.get_env(:libcluster, :topologies) || []
    cluster_args = [topologies, [name: Wire.ClusterSupervisor]]

    children = [
      {Cluster.Supervisor, cluster_args},
      Wire.ClusterConnector
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule Wire.ClusterConnector do
  use GenServer
  require Logger

  @interval_ms 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Only activate the connection polling if we are explicitly running in
    # Docker Compose with EPMD strategy hosts configured.
    hosts = get_epmd_hosts()

    if hosts != [] and System.get_env("DOCKER_COMPOSE") == "true" do
      Logger.info("[ClusterConnector] EPMD topology detected in Compose. Activating connection polling.")
      schedule_check()
      {:ok, %{hosts: hosts}}
    else
      Logger.debug("[ClusterConnector] Standalone or Kubernetes environment detected. Polling disabled.")
      {:ok, %{hosts: []}}
    end
  end

  @impl true
  def handle_info(:check_connections, %{hosts: [_ | _]} = state) do
    for host <- state.hosts do
      unless host in Node.list() do
        Logger.info("[ClusterConnector] Attempting to connect to remote node: #{inspect(host)}")
        case Node.ping(host) do
          :pong -> Logger.info("[ClusterConnector] Successfully connected to #{inspect(host)}")
          :pang -> Logger.debug("[ClusterConnector] Host #{inspect(host)} is not reachable yet.")
        end
      end
    end

    schedule_check()
    {:noreply, state}
  end

  def handle_info(:check_connections, state) do
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_connections, @interval_ms)
  end

  defp get_epmd_hosts do
    topologies = Application.get_env(:libcluster, :topologies) || []
    docker_compose_config = Keyword.get(topologies, :docker_compose) || []
    config = Keyword.get(docker_compose_config, :config) || []
    Keyword.get(config, :hosts) || []
  end
end

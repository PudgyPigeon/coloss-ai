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
      {Cluster.Supervisor, cluster_args}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

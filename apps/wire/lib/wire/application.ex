defmodule Wire.Application do
  use Application

  @impl true
  def start(_type, _args) do
    topologies = Application.get_env(:libcluster, :topologies) || []
    Wire.Supervisor.start_link(topologies)
  end
end

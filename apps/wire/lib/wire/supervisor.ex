defmodule Wire.Supervisor do
  @moduledoc """
  Root supervisor for the Wire application supervision tree.
  """

  use Supervisor

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  @spec init(term()) :: {:ok, {:supervisor.sup_flags(), [Supervisor.child_spec()]}} | :ignore
  def init(_args) do
    children = [
      Wire.ProcessGroup,
      Wire.Cluster,
      Wire.Telemetry,
      WireWeb.Endpoint
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

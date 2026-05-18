defmodule Wire.Telemetry do
  @moduledoc """
  Telemetry supervision and metric definition for the Wire application.
  """

  use Supervisor
  import Telemetry.Metrics

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  @spec init(term()) :: {:ok, {:supervisor.sup_flags(), [Supervisor.child_spec()]}} | :ignore
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec metrics() :: [struct()]
  def metrics do
    [
      # Phoenix endpoint metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        description: "The time spent processing requests"
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond},
        description: "The time spent dispatching routes"
      ),
      # Standard Erlang BEAM VM metrics (rendered out-of-the-box on other nodes)
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.system_counts.process_count")
    ]
  end

  @spec periodic_measurements() :: list()
  defp periodic_measurements do
    []
  end
end

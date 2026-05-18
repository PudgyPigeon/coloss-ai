defmodule Wire.Swarm do
  @moduledoc """
  Core domain context for interacting with the agentic Don Erleone clustered swarm nodes.
  Acts as the primary backend client boundary for the web frontend (WireWeb).
  """

  @doc """
  Discovers the clustered Don Erleone orchestrator node.
  Falls back to the local node name if no cluster is connected.
  """
  def discover_node do
    nodes = [node() | Node.list()]
    Enum.find(nodes, &String.contains?(to_string(&1), "don_erleone")) || node()
  end

  @doc """
  Checks if the local node is clustered with a Don Erleone node.
  """
  def clustered? do
    discover_node() != node()
  end

  @doc """
  Fetches real-time orchestrator pool metrics and BEAM vital stats.
  """
  def get_metrics(node \\ discover_node()) do
    case :rpc.call(node, :de_dashboard_api, :get_metrics, []) do
      {:badrpc, _} -> default_metrics()
      metrics when is_map(metrics) -> metrics
      _ -> default_metrics()
    end
  end

  @doc """
  Fetches recent swarm missions ledger from the Mnesia database.
  """
  def get_recent_missions(limit, node \\ discover_node()) do
    case :rpc.call(node, :de_dashboard_api, :get_recent_missions, [limit]) do
      {:badrpc, _} -> []
      list when is_list(list) -> list
      _ -> []
    end
  end

  @doc """
  Dispatches a new reasoning or simulation mission request asynchronously to the
  Don Erleone orchestrator's reasoning pool.
  """
  def dispatch_mission(prompt, caller_info, node \\ discover_node()) do
    # caller_info is expected to be a tuple of {caller_pid, reference_tag}
    :rpc.call(node, :de_consigliere, :handle_mission, [
      "dashboard-sim-session",
      prompt,
      caller_info
    ])
  end

  defp default_metrics do
    %{
      consigliere: %{
        active: 0,
        idle: 5,
        overflow: 0,
        max_size: 5,
        max_overflow: 15,
        status: :offline
      },
      caporegime: %{
        active: 0,
        idle: 3,
        overflow: 0,
        max_size: 3,
        max_overflow: 10,
        status: :offline
      },
      system_vitals: %{memory_bytes: 0, process_count: 0, run_queue: 0}
    }
  end
end

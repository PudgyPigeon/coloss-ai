defmodule Wire.Swarm do
  @moduledoc """
  Core domain context for interacting with the agentic Don Erleone clustered swarm nodes.
  Acts as the primary backend client boundary for the web frontend (WireWeb).
  """

  @gigabyte 1_073_741_824
  @megabyte 1_048_576
  @kilobyte 1_024

  @doc """
  Discovers the clustered Don Erleone orchestrator node.
  Falls back to the local node name if no cluster is connected.
  """
  @spec discover_node() :: node()
  def discover_node do
    nodes = [node() | Node.list()]
    Enum.find(nodes, &String.contains?(to_string(&1), "don_erleone")) || node()
  end

  @doc """
  Checks if the local node is clustered with a Don Erleone node.
  """
  @spec clustered?() :: boolean()
  def clustered? do
    discover_node() != node()
  end

  @doc """
  Fetches real-time orchestrator pool metrics and BEAM vital stats.
  """
  @spec get_metrics(node()) :: map()
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
  @spec get_recent_missions(integer(), node()) :: list()
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
  @spec dispatch_mission(binary(), {pid(), reference()}, node()) :: term()
  def dispatch_mission(prompt, caller_info, node \\ discover_node()) do
    # caller_info is expected to be a tuple of {caller_pid, reference_tag}
    :rpc.call(node, :de_consigliere, :handle_mission, [
      "dashboard-sim-session",
      prompt,
      caller_info
    ])
  end

  @doc """
  Aggregates, formats, and structures all live telemetry metrics and ledger status
  for direct presentation in the Swarm Dashboard.
  """
  @spec get_dashboard_data() :: map()
  def get_dashboard_data do
    don_node = discover_node()
    is_conn = clustered?()
    metrics = get_metrics(don_node)

    missions =
      case get_recent_missions(6, don_node) do
        [] -> mock_missions()
        list -> list
      end

    vitals = metrics.system_vitals

    formatted_vitals = %{
      vitals |
      memory_bytes: format_memory(vitals.memory_bytes)
    }

    %{
      don_erleone_node: don_node,
      is_connected: is_conn,
      consigliere: metrics.consigliere,
      caporegime: metrics.caporegime,
      system_vitals: formatted_vitals,
      missions: missions,
      nodes: [node() | Node.list()]
    }
  end

  @spec format_memory(integer()) :: String.t()
  defp format_memory(bytes) do
    cond do
      bytes == 0 -> "0 B"
      bytes > @gigabyte -> "#{Float.round(bytes / @gigabyte, 2)} GB"
      bytes > @megabyte -> "#{Float.round(bytes / @megabyte, 1)} MB"
      true -> "#{Float.round(bytes / @kilobyte, 0)} KB"
    end
  end

  @spec default_metrics() :: map()
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

  @spec mock_missions() :: [map()]
  defp mock_missions do
    [
      %{
        id: 4101,
        session_id: "sess-99b821",
        intent: "List Kubernetes Pods",
        raw_prompt: "Get all active pods in standard namespaces.",
        status: :completed,
        result:
          "[{\"pod\":\"postgres-0\",\"status\":\"Running\"},{\"pod\":\"ollama-7f\",\"status\":\"Running\"}]",
        error: "nil",
        timestamp: System.system_time(:second) - 60
      },
      %{
        id: 4102,
        session_id: "sess-11aa23",
        intent: "Scale Deployments",
        raw_prompt: "Scale the openwebui frontend pool replica count to 3.",
        status: :in_progress,
        result: "nil",
        error: "nil",
        timestamp: System.system_time(:second) - 30
      },
      %{
        id: 4103,
        session_id: "sess-bb7742",
        intent: "Evaluate ArgoCD Sync Status",
        raw_prompt: "Check if the app-of-apps has been synchronized successfully.",
        status: :failed,
        result: "nil",
        error: "{error, connection_timeout}",
        timestamp: System.system_time(:second) - 180
      }
    ]
  end
end

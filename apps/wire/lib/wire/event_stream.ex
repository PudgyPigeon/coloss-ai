defmodule Wire.EventStream do
  @moduledoc """
  Domain boundary wrapping the Erlang `:pg` process group registry.
  Decouples the web and core layers from specific VM-level pub/sub implementations.
  """

  @topic :swarm_dashboard_events

  @doc """
  Subscribes the calling process to the real-time swarm telemetry event stream.
  """
  @spec subscribe() :: :ok
  def subscribe do
    :pg.join(@topic, self())
  end

  @doc """
  Broadcasts an operational signal event to all active subscribers across the cluster.
  """
  @spec broadcast(atom(), integer()) :: :ok
  def broadcast(action, mission_id) do
    case :pg.get_members(@topic) do
      pids when is_list(pids) ->
        Enum.each(pids, &send(&1, {:mission_event, action, mission_id}))
        :ok
      _ ->
        :ok
    end
  end
end

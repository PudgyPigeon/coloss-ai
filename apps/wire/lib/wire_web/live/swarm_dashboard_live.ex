defmodule WireWeb.SwarmDashboardLive do
  @moduledoc """
  Phoenix LiveView controller logic for the Swarm real-time monitoring console.
  Delegates all presentation formatting, metrics aggregation, and data mapping to
  the `Wire.Swarm` domain context, keeping this module purely focused on state-handling.
  """

  use Phoenix.LiveView
  import WireWeb.SwarmComponents

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to real-time stats updates and distributed process group events
      :timer.send_interval(3000, self(), :tick)
      Wire.EventStream.subscribe()
    end

    socket =
      socket
      |> assign(:mission_prompt, "")
      |> assign(:execution_status, :idle)
      |> assign(:execution_result, nil)
      |> assign(:mission_logs, [])
      |> assign(:telemetry_logs, [])
      |> assign(:active_tab, "overview")
      |> assign(:theme, "default")
      |> log_event("SYSTEM: Swarm V#{Wire.Application.version()} deck online. Real-time push streams enabled.")
      |> log_event(
        "SYSTEM: Subscribed to Distributed Erlang process group 'swarm_dashboard_events'."
      )
      |> update_stats()

    {:ok, socket}
  end

  # --- LiveView Events ---

  @impl true
  @spec handle_event(binary(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("mission_change", %{"prompt" => prompt}, socket) do
    {:noreply, assign(socket, :mission_prompt, prompt)}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("change_theme", %{"theme" => theme}, socket) do
    {:noreply,
     socket
     |> assign(:theme, theme)
     |> push_event("theme_changed", %{theme: theme})}
  end

  @impl true
  def handle_event("submit_mission", _params, socket) do
    prompt = socket.assigns.mission_prompt

    if prompt != "" do
      if Wire.Swarm.clustered?() do
        Wire.Swarm.dispatch_mission(prompt, {self(), make_ref()})

        {:noreply,
         socket
         |> assign(:execution_status, :processing)
         |> assign(:execution_result, nil)
         |> log_event("SYSTEM: Dispatched mission to reasoning pool (de_consigliere_pool).")}
      else
        # Mock offline compilation feedback for isolated dev hosts
        Process.send_after(self(), {:local_mock_done, prompt}, 2000)

        {:noreply,
         socket
         |> assign(:execution_status, :processing)
         |> assign(:execution_result, nil)
         |> log_event("SYSTEM: Standalone mission trigger. Offline sandbox response simulated.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_mission", _params, socket) do
    {:noreply,
     socket
     |> assign(:mission_prompt, "")
     |> assign(:execution_status, :idle)
     |> assign(:execution_result, nil)}
  end

  # --- Info / Message Handlers ---

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(:tick, socket) do
    {:noreply, update_stats(socket)}
  end

  @impl true
  def handle_info({:mission_event, action, mission_id}, socket) do
    {:noreply,
     socket
     |> log_event(
       "TELEMETRY PUSH: Mission ##{mission_id} was #{action} instantly in don-erleone."
     )
     |> update_stats()}
  end

  @impl true
  def handle_info({:telemetry_event, event, measurements metadata}, socket) do
    event_name = Enum.join(event, "")
    measurements_str = inspect(measurements)
    metadata_str = inspect(metadata, limit: 5, printable_list: 100)
    msg = "TELEMETRY: [#{event_name} | Metrics: #{measurements_str} | Metadata: #{metadata_str}}]"
    {:noreply, log_event(socket, msg)}
  end

  @impl true
  def handle_info({:custom_log, msg}, socket) do
    {:noreply, log_event(socket, msg)}
  end

  @impl true
  def handle_info({tag, {:done, result, _mid}}, socket) when is_reference(tag) do
    handle_info({tag, {:done, result}}, socket)
  end

  @impl true
  def handle_info({tag, {:chunk, _content, _mid}}, socket) when is_reference(tag) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({tag, {:done, result}}, socket) when is_reference(tag) do
    formatted_result =
      case result do
        binary when is_binary(binary) -> binary
        other -> inspect(other)
      end

    socket =
      socket
      |> assign(:execution_status, :completed)
      |> assign(:execution_result, formatted_result)
      |> log_event("MISSION CONTROL: Mission completed. Result integrated.")
      |> update_stats()

    {:noreply, socket}
  end

  @impl true
  def handle_info({tag, {:error, reason}}, socket) when is_reference(tag) do
    socket =
      socket
      |> assign(:execution_status, :failed)
      |> assign(:execution_result, "Error: #{inspect(reason)}")
      |> log_event("INFRASTRUCTURE ERROR: Mission execution failed.")
      |> update_stats()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:local_mock_done, prompt}, socket) do
    result =
      "Local simulated feedback for: \"#{prompt}\". Standalone node completed mission mock execution successfully using background thread."

    {:noreply,
     socket
     |> assign(:execution_status, :completed)
     |> assign(:execution_result, result)
     |> log_event("SYSTEM: Simulated offline mission execution complete.")}
  end

  # =============================================================================
  # Telemetry / State Helpers
  # =============================================================================

  @spec update_stats(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp update_stats(socket) do
    data = Wire.Swarm.get_dashboard_data()
    tree = Wire.Swarm.get_supervision_tree()

    socket
    |> assign(data)
    |> push_event("update_echarts_nodes", tree)
  end

  @spec log_event(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp log_event(socket, msg) do
    new_log = %{time: current_time_str(), msg: msg}
    assign(socket, :logs, [new_log | socket.assigns.logs])
  end

  @spec current_time_str() :: String.t()
  defp current_time_str do
    DateTime.utc_now() |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 8)
  end

  # =============================================================================
  # LiveView Template is loaded from: swarm_dashboard_live.html.heex
  # =============================================================================
end

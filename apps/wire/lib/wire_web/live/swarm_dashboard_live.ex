defmodule WireWeb.SwarmDashboardLive do
  use Phoenix.LiveView
  import WireWeb.SwarmComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Tick every 3 seconds for system metrics updates (CPU/memory)
      :timer.send_interval(3000, self(), :tick)

      # Subscribe to real-time process group updates from Erlang don-erleone
      _ = :pg.start_link()
      :pg.join(:swarm_dashboard_events, self())
    end

    initial_logs = [
      %{
        time: current_time_str(),
        msg: "SYSTEM: Swarm V2 deck online. Real-time push streams enabled."
      },
      %{
        time: current_time_str(),
        msg: "SYSTEM: Subscribed to Distributed Erlang process group 'swarm_dashboard_events'."
      }
    ]

    socket =
      socket
      |> assign(:simulate_prompt, "")
      |> assign(:simulation_status, :idle)
      |> assign(:simulation_result, nil)
      |> assign(:logs, initial_logs)
      |> update_stats()

    {:ok, socket}
  end

  # --- LiveView Events ---

  @impl true
  def handle_event("simulate_change", %{"prompt" => prompt}, socket) do
    {:noreply, assign(socket, :simulate_prompt, prompt)}
  end

  @impl true
  def handle_event("submit_simulation", _params, socket) do
    prompt = socket.assigns.simulate_prompt
    is_connected = Wire.Swarm.clustered?()

    if prompt != "" do
      if is_connected do
        caller = self()
        tag = make_ref()

        # Async dispatch using the Swarm domain API
        Wire.Swarm.dispatch_mission(prompt, {caller, tag})

        new_log = %{
          time: current_time_str(),
          msg: "SYSTEM: Dispatched simulated mission to reasoning pool (de_consigliere_pool)."
        }

        {:noreply,
         socket
         |> assign(:simulation_status, :processing)
         |> assign(:simulation_result, nil)
         |> assign(:logs, [new_log | socket.assigns.logs])}
      else
        # Mock offline completion for presentation
        new_log = %{
          time: current_time_str(),
          msg: "SYSTEM: Local simulation trigger. Offline demo response simulated."
        }

        # Set timer to trigger simulated offline done
        Process.send_after(self(), {:local_mock_done, prompt}, 2000)

        {:noreply,
         socket
         |> assign(:simulation_status, :processing)
         |> assign(:simulation_result, nil)
         |> assign(:logs, [new_log | socket.assigns.logs])}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_simulation", _params, socket) do
    {:noreply,
     socket
     |> assign(:simulate_prompt, "")
     |> assign(:simulation_status, :idle)
     |> assign(:simulation_result, nil)}
  end

  # --- Info / Message Handlers ---

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, update_stats(socket)}
  end

  # Real-time event push from Erlang (Sub-millisecond reactivity)
  @impl true
  def handle_info({:mission_event, action, mission_id}, socket) do
    event_msg =
      "TELEMETRY PUSH: Mission ##{mission_id} was #{action} instantly in don-erleone orchestrator."

    new_log = %{time: current_time_str(), msg: event_msg}

    {:noreply,
     socket
     |> assign(:logs, [new_log | socket.assigns.logs])
     |> update_stats()}
  end

  # Handle the asynchronous result sent back from the clustered Erlang node
  @impl true
  def handle_info({tag, {:done, result}}, socket) when is_reference(tag) do
    new_log = %{
      time: current_time_str(),
      msg: "COGNITIVE DECK: Mission completed. Result integrated."
    }

    formatted_result =
      case result do
        binary when is_binary(binary) -> binary
        other -> inspect(other)
      end

    socket =
      socket
      |> assign(:simulation_status, :completed)
      |> assign(:simulation_result, formatted_result)
      |> assign(:logs, [new_log | socket.assigns.logs])
      |> update_stats()

    {:noreply, socket}
  end

  @impl true
  def handle_info({tag, {:error, reason}}, socket) when is_reference(tag) do
    new_log = %{time: current_time_str(), msg: "INFRASTRUCTURE ERROR: Mission execution failed."}

    socket =
      socket
      |> assign(:simulation_status, :failed)
      |> assign(:simulation_result, "Error: #{inspect(reason)}")
      |> assign(:logs, [new_log | socket.assigns.logs])
      |> update_stats()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:local_mock_done, prompt}, socket) do
    result =
      "Local simulated feedback for: \"#{prompt}\". Standalone node completed mission mock execution successfully using background thread."

    new_log = %{
      time: current_time_str(),
      msg: "SYSTEM: Simulated offline mission execution complete."
    }

    {:noreply,
     socket
     |> assign(:simulation_status, :completed)
     |> assign(:simulation_result, result)
     |> assign(:logs, [new_log | socket.assigns.logs])}
  end

  # =============================================================================
  # Telemetry / State Updates
  # =============================================================================

  defp update_stats(socket) do
    don_erleone_node = Wire.Swarm.discover_node()
    is_connected = Wire.Swarm.clustered?()

    metrics = Wire.Swarm.get_metrics(don_erleone_node)
    consigliere = metrics.consigliere
    caporegime = metrics.caporegime
    system_vitals = metrics.system_vitals

    missions =
      case Wire.Swarm.get_recent_missions(6, don_erleone_node) do
        [] -> mock_missions()
        list -> list
      end

    socket
    |> assign(:don_erleone_node, don_erleone_node)
    |> assign(:is_connected, is_connected)
    |> assign(:consigliere, consigliere)
    |> assign(:caporegime, caporegime)
    |> assign(:system_vitals, system_vitals)
    |> assign(:missions, missions)
    |> assign(:nodes, [node() | Node.list()])
  end

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

  defp format_memory(bytes) do
    cond do
      bytes == 0 -> "0 B"
      bytes > 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes > 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      true -> "#{Float.round(bytes / 1024, 0)} KB"
    end
  end

  defp current_time_str do
    DateTime.utc_now() |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 8)
  end

  # =============================================================================
  # LiveView Template
  # =============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="/css/swarm.css">

    <div class="cyber-grid"></div>
    <div class="scanlines"></div>

    <div class="swarm-wrapper">
      <!-- Top Operational Deck Header -->
      <div class="deck-header">
        <h1 class="brand-title">
          <svg style="width: 24px; height: 24px; fill: currentColor;" viewBox="0 0 24 24">
            <path d="M12 2L2 22h20L12 2zm0 3.99L19.53 19H4.47L12 5.99zM13 16h-2v2h2v-2zm0-6h-2v4h2v-4z"/>
          </svg>
          The Wire // Swarm V2 deck
        </h1>

        <div class="status-badge">
          <%= if @is_connected do %>
            <span class="pulse-indicator" style="color: #00ff88; background-color: #00ff88;"></span>
            <span style="color: #00ff88;">CLUSTERED WITH <%= @don_erleone_node %></span>
          <% else %>
            <span class="pulse-indicator" style="color: #ff9f0a; background-color: #ff9f0a;"></span>
            <span style="color: #ff9f0a;">STANDALONE DECK (MOCK TELEMETRY)</span>
          <% end %>
        </div>
      </div>

      <!-- Agent Pool & Orchestrator Vitals Grid (Top Tier Columns) -->
      <div class="agent-pool-flex">
        <!-- Consigliere (Reasoning Agents) Card -->
        <.pool_card title="Consigliere Pool (Reasoning Agents)" pool={@consigliere} type={:gold} />

        <!-- Caporegime (Execution Agents) Card -->
        <.pool_card title="Caporegime Pool (Execution Agents)" pool={@caporegime} type={:green} />

        <!-- System Vitals (Real-time Erlang Metrics) -->
        <div class="glass-card">
          <div class="pool-title">
            <span>Orchestrator System Vitals</span>
            <span style="font-size: 11px; color: #00ff88; font-family: 'JetBrains Mono', monospace; background: rgba(0,255,136,0.1); padding: 2px 6px; border-radius: 4px; border: 1px solid rgba(0,255,136,0.15)">
              REAL-TIME
            </span>
          </div>

          <div style="margin-top: 10px;">
            <div class="vital-row">
              <span class="vital-label">BEAM Allocated Memory</span>
              <span class="vital-value"><%= format_memory(@system_vitals.memory_bytes) %></span>
            </div>

            <div class="vital-row">
              <span class="vital-label">Active Processes count</span>
              <span class="vital-value"><%= @system_vitals.process_count %></span>
            </div>

            <div class="vital-row">
              <span class="vital-label">Scheduler Run Queue</span>
              <span class="vital-value"><%= @system_vitals.run_queue %></span>
            </div>
          </div>
        </div>
      </div>

      <!-- Main Operational Dashboard Layout Grid -->
      <div class="dashboard-grid">

        <!-- Left Side: Live Swarm Missions and Interactive Test -->
        <div>
          <!-- Mission Simulation Suite -->
          <div class="glass-card">
            <h3 style="margin-top: 0; font-weight: 800; text-transform: uppercase; font-size: 16px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); padding-bottom: 10px; color: #ffd700;">
              Mission simulation console
            </h3>

            <form phx-submit="submit_simulation" phx-change="simulate_change">
              <input type="text"
                     name="prompt"
                     value={@simulate_prompt}
                     placeholder="Enter a directive for the swarm (e.g. 'Deploy pod in namespace test')..."
                     class="form-input"
                     autocomplete="off"
                     disabled={@simulation_status == :processing} />

              <div style="display: flex; gap: 12px;">
                <button type="submit" class="deck-btn" disabled={@simulation_status == :processing or @simulate_prompt == ""}>
                  <%= if @simulation_status == :processing do %>
                    <svg style="animation: spin 1s linear infinite; width: 16px; height: 16px; margin-right: 4px;" fill="none" viewBox="0 0 24 24">
                      <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" style="opacity: 0.25;"></circle>
                      <path fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
                    </svg>
                    Executing consult...
                  <% else %>
                    Deploy mission
                  <% end %>
                </button>

                <%= if @simulation_status != :idle do %>
                  <button type="button" phx-click="clear_simulation" class="deck-btn" style="background: rgba(255, 255, 255, 0.08); color: #fff; border: 1px solid rgba(255, 255, 255, 0.15);">
                    Reset
                  </button>
                <% end %>
              </div>
            </form>

            <%= if @simulation_result do %>
              <div style="margin-top: 20px; background: rgba(3, 4, 6, 0.95); border: 1px solid rgba(212, 175, 55, 0.25); border-radius: 8px; padding: 14px; font-family: 'JetBrains Mono', monospace;">
                <span style="font-weight: 800; font-size: 12px; text-transform: uppercase; color: #ffd700; display: block; margin-bottom: 6px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); padding-bottom: 4px;">
                  Simulation Result Payload
                </span>
                <pre style="font-size: 13px; color: #33ff33; margin: 0; white-space: pre-wrap; word-break: break-all; line-height: 1.5;"><%= @simulation_result %></pre>
              </div>
            <% end %>
          </div>

          <!-- Active & Recent Swarm Missions -->
          <div class="glass-card">
            <h3 style="margin-top: 0; font-weight: 800; text-transform: uppercase; font-size: 16px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); padding-bottom: 10px; color: #ffd700;">
              Swarm Missions Ledger (Mnesia Real-time Sync)
            </h3>

            <div style="margin-top: 14px;">
              <%= if Enum.empty?(@missions) do %>
                <div style="padding: 24px 0; text-align: center; color: #718096; font-size: 14px;">
                  No active missions found in Mnesia ledger.
                </div>
              <% else %>
                <%= for mission <- @missions do %>
                  <.mission_card mission={mission} />
                <% end %>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Right Side: BEAM Nodes and System Feeds -->
        <div>
          <!-- BEAM Cluster Topology Nodes -->
          <div class="glass-card">
            <h3 style="margin-top: 0; font-weight: 800; text-transform: uppercase; font-size: 16px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); padding-bottom: 10px; color: #ffd700;">
              BEAM Cluster nodes
            </h3>

            <div style="margin-top: 14px;">
              <%= for node_name <- @nodes do %>
                <.node_chip node_name={node_name} current_node={node()} />
              <% end %>
            </div>
          </div>

          <!-- Real-Time Operational Signals Feed -->
          <div class="glass-card">
            <h3 style="margin-top: 0; font-weight: 800; text-transform: uppercase; font-size: 16px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); padding-bottom: 10px; color: #ffd700;">
              Operational Signals Feed
            </h3>

            <div class="log-console" style="margin-top: 14px;">
              <%= for log <- @logs do %>
                <div class="log-line">
                  <span class="timestamp-col">[<%= log.time %>]</span>
                  <span><%= log.msg %></span>
                </div>
              <% end %>
            </div>
          </div>
        </div>

      </div>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.10/priv/static/phoenix.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/phoenix_live_view@0.20.2/priv/static/phoenix_live_view.min.js"></script>
    <script>
      let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
      let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {params: {_csrf_token: csrfToken}});
      liveSocket.connect();
    </script>
    """
  end
end

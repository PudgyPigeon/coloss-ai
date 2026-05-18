defmodule WireWeb.SwarmComponents do
  use Phoenix.Component

  attr(:title, :string, required: true)
  attr(:pool, :map, required: true)
  # :gold or :green
  attr(:type, :atom, default: :gold)

  def pool_card(assigns) do
    ~H"""
    <div class="glass-card">
      <div class="pool-title">
        <span><%= @title %></span>
        <span style="font-size: 11px; color: #cbd5e0; font-family: 'JetBrains Mono', monospace; background: rgba(255,255,255,0.05); padding: 2px 6px; border-radius: 4px;">
          <%= @pool.status %>
        </span>
      </div>

      <div class="stat-number-label">
        <%= @pool.active %>
        <span class="stat-total-label">/ <%= @pool.max_size %> Active (Capacity <%= @pool.max_size + @pool.max_overflow %>)</span>
      </div>

      <div class="progress-bar-bg" style="margin-top: 14px;">
        <% percent = (@pool.active / (@pool.max_size + @pool.max_overflow)) * 100 %>
        <div class={if @type == :green, do: "progress-fill-green", else: "progress-fill-gold"} style={"width: #{percent}%"}></div>
      </div>

      <div style="display: flex; justify-content: space-between; font-size: 12px; color: #718096; margin-top: 8px;">
        <span>Idle: <%= @pool.idle %></span>
        <span>Overflow: <%= @pool.overflow %> / <%= @pool.max_overflow %></span>
      </div>
    </div>
    """
  end

  attr(:mission, :map, required: true)

  def mission_card(assigns) do
    ~H"""
    <div class="mission-item">
      <div class="mission-header-row">
        <span style="font-family: 'JetBrains Mono', monospace; font-weight: 700; font-size: 13px; color: #fff;">
          MISSION #<%= @mission.id %>
        </span>
        <span class={"status-pill status-#{@mission.status}"}>
          <%= @mission.status %>
        </span>
      </div>

      <div style="font-size: 14px; margin: 6px 0; font-weight: 600; color: #cbd5e0;">
        <span style="color: #a0aec0; font-size: 12px;">Intent:</span> <%= @mission.intent %>
      </div>

      <div style="font-size: 13px; color: #718096; font-family: 'JetBrains Mono', monospace; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
        Prompt: <%= @mission.raw_prompt %>
      </div>

      <%= if @mission.result != "nil" and @mission.result != "undefined" do %>
        <div style="margin-top: 8px; font-size: 12px; color: #00ff88; background: rgba(0, 255, 136, 0.05); padding: 8px 12px; border-radius: 6px; border: 1px solid rgba(0, 255, 136, 0.15); font-family: 'JetBrains Mono', monospace; word-break: break-all;">
          <span style="font-weight: 800; font-size: 10px; text-transform: uppercase; display: block; margin-bottom: 2px; color: #a0aec0;">Result:</span>
          <%= @mission.result %>
        </div>
      <% end %>

      <%= if @mission.error != "nil" and @mission.error != "undefined" do %>
        <div style="margin-top: 8px; font-size: 12px; color: #ff3b30; background: rgba(255, 59, 48, 0.05); padding: 8px 12px; border-radius: 6px; border: 1px solid rgba(255, 59, 48, 0.15); font-family: 'JetBrains Mono', monospace; word-break: break-all;">
          <span style="font-weight: 800; font-size: 10px; text-transform: uppercase; display: block; margin-bottom: 2px; color: #a0aec0;">Error:</span>
          <%= @mission.error %>
        </div>
      <% end %>
    </div>
    """
  end

  attr(:node_name, :any, required: true)
  attr(:current_node, :any, required: true)

  def node_chip(assigns) do
    ~H"""
    <div class="node-chip">
      <span><%= @node_name %></span>
      <%= if @node_name == @current_node do %>
        <span style="font-size: 10px; background: rgba(212, 175, 55, 0.2); color: #ffd700; padding: 2px 6px; border-radius: 4px; font-weight: 800;">DECK HOST</span>
      <% else %>
        <span style="font-size: 10px; background: rgba(0, 255, 136, 0.2); color: #00ff88; padding: 2px 6px; border-radius: 4px; font-weight: 800;">CLUSTERED</span>
      <% end %>
    </div>
    """
  end
end

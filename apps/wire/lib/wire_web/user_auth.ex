defmodule WireWeb.UserAuth do
  @moduledoc """
  Handles conditional authentication logic for Phoenix LiveView mounts.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  @doc """
  Ensures that a user is authenticated. 
  If authentication is disabled globally, a mock developer user profile is automatically assigned.
  """
  @spec on_mount(:ensure_authenticated, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:ensure_authenticated, _params, session, socket) do
    cond do
      # 1. Auth is disabled globally: Inject a local developer user profile
      not auth_enabled?() ->
        developer_user = %{
          email: "dev-capo@local.internal",
          name: "Local Developer (Admin)",
          roles: ["caporegime", "admin"]
        }

        {:cont, assign(socket, :current_user, developer_user)}

      # 2. Auth is enabled and user is logged in: Let them through
      user = session["current_user"] ->
        {:cont, assign(socket, :current_user, user)}

      # 3. Auth is enabled and no session exists: Force Auth0 redirect
      true ->
        {:halt, redirect(socket, to: "/auth/auth0")}
    end
  end

  @spec auth_enabled?() :: boolean()
  defp auth_enabled? do
    Application.get_env(:wire, :auth_enabled, false)
  end
end

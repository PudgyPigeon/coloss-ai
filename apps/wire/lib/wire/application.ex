defmodule Wire.Application do
  @moduledoc """
  Application entrypoint for the Wire service.
  Defines the supervision tree for clustering and web endpoint components.
  """

  use Application

  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    Wire.Supervisor.start_link([])
  end
end

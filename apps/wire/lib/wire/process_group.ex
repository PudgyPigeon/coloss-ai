defmodule Wire.ProcessGroup do
  @moduledoc """
  Supervised wrapper around the Erlang `:pg` process group manager.
  Guarantees proper startup and lifecycle management within the Elixir supervision tree.
  """

  @doc """
  Starts the Erlang `:pg` process group manager.
  By default, starts the default scope named `:pg`.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    scope = Keyword.get(opts, :scope, :pg)

    if scope == :pg do
      :pg.start_link()
    else
      :pg.start_link(scope)
    end
  end

  @doc """
  Returns the child specification to allow supervision.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end
end

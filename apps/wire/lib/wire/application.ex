defmodule Wire.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Wire.Supervisor.start_link([])
  end
end

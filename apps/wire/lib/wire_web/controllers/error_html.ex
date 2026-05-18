defmodule WireWeb.ErrorHTML do
  @moduledoc false

  @spec render(template :: binary() | atom(), map()) :: binary()
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

defmodule NexusWeb.ErrorJSON do
  @moduledoc """
  Error responses for JSON API.
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end

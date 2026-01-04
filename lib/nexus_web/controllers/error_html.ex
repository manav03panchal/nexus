defmodule NexusWeb.ErrorHTML do
  @moduledoc """
  Error pages for HTML responses.
  """

  use NexusWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

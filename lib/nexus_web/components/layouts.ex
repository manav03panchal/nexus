defmodule NexusWeb.Layouts do
  @moduledoc """
  Layout components for the Nexus web dashboard.
  """

  use NexusWeb, :html

  embed_templates("layouts/*")
end

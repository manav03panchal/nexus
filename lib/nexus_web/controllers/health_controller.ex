defmodule NexusWeb.HealthController do
  @moduledoc """
  Health check endpoint for the web dashboard.
  """

  use NexusWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok", version: Application.spec(:nexus, :vsn) |> to_string()})
  end
end

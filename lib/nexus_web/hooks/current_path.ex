defmodule NexusWeb.Hooks.CurrentPath do
  @moduledoc """
  LiveView hook that injects the current path into socket assigns.

  This is used by the navigation component to highlight the active route.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> attach_hook(:current_path, :handle_params, &handle_params/3)}
  end

  defp handle_params(_params, uri, socket) do
    %URI{path: path} = URI.parse(uri)
    {:cont, assign(socket, :current_path, path || "/")}
  end
end

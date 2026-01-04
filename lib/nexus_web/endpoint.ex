defmodule NexusWeb.Endpoint do
  @moduledoc """
  Phoenix endpoint for the Nexus web dashboard.
  """

  use Phoenix.Endpoint, otp_app: :nexus

  @static_paths ~w(assets fonts images favicon.ico robots.txt)

  # The session will be stored in the cookie and signed
  @session_options [
    store: :cookie,
    key: "_nexus_web_key",
    signing_salt: "nexus_web",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false
  )

  # Serve static files from priv/static
  plug(Plug.Static,
    at: "/",
    from: {:nexus, "priv/static"},
    gzip: false,
    only: @static_paths
  )

  # Code reloading can be explicitly enabled under the :code_reloader config
  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(NexusWeb.Router)
end

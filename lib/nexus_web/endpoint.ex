# sobelow_skip ["Config.CSWH"]
defmodule NexusWeb.Endpoint do
  @moduledoc """
  Phoenix endpoint for the Nexus web dashboard.

  Note: check_origin is disabled because this is a local development tool
  that may be accessed via different hostnames (localhost, 127.0.0.1, LAN IP).
  """

  use Phoenix.Endpoint, otp_app: :nexus

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

  # Static assets are served via AssetsController for escript compatibility

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

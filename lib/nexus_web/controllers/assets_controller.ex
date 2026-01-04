defmodule NexusWeb.AssetsController do
  @moduledoc """
  Serves embedded static assets for the web dashboard.

  Since escripts don't include priv directory, we embed assets at compile time.
  """

  use NexusWeb, :controller

  @external_resource "priv/static/assets/app.css"
  @external_resource "priv/static/assets/app.js"
  @external_resource "priv/static/assets/nexus-logo.png"

  @app_css File.read!("priv/static/assets/app.css")
  @app_js File.read!("priv/static/assets/app.js")
  @logo_png File.read!("priv/static/assets/nexus-logo.png")

  def css(conn, _params) do
    conn
    |> put_resp_content_type("text/css")
    |> send_resp(200, @app_css)
  end

  def js(conn, _params) do
    conn
    |> put_resp_content_type("application/javascript")
    |> send_resp(200, @app_js)
  end

  def logo(conn, _params) do
    conn
    |> put_resp_content_type("image/png")
    |> put_resp_header("cache-control", "public, max-age=31536000")
    |> send_resp(200, @logo_png)
  end
end

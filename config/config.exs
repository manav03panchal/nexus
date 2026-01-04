import Config

# Hammer rate limiter configuration
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

# Phoenix web dashboard configuration
config :nexus, NexusWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: NexusWeb.ErrorHTML, json: NexusWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: NexusWeb.PubSub,
  live_view: [signing_salt: "nexus_lv_salt"]

# Configure esbuild
config :esbuild,
  version: "0.17.11",
  nexus_web: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../../../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../lib/nexus_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind
config :tailwind,
  version: "3.4.0",
  nexus_web: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../../../priv/static/assets/app.css
    ),
    cd: Path.expand("../lib/nexus_web/assets", __DIR__)
  ]

# Import environment specific config
import_config "#{config_env()}.exs"

import Config

# Production-specific configuration
config :logger, level: :info

# Web dashboard production config - configured at runtime
config :nexus, NexusWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: false

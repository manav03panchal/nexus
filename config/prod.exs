import Config

# Production-specific configuration
config :logger, level: :info

# Web dashboard production config - configured at runtime
# Note: cache_static_manifest disabled for escript compatibility
config :nexus, NexusWeb.Endpoint, server: false

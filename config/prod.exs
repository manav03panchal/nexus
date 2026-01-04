import Config

# Production-specific configuration - suppress verbose logs
config :logger, level: :warning

# Web dashboard config - server started dynamically at runtime via Application.start_link

import Config

# Test-specific configuration
config :logger, level: :warning

# Disable web dashboard in tests
config :nexus, NexusWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_is_at_least_64_bytes_long_for_testing_only",
  server: false

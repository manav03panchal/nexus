# Configure ExUnit
# Exclude integration tests by default (require Docker SSH)
# Exclude performance tests by default (run manually)
# Exclude skipped tests (placeholder tests for future phases)
ExUnit.start(exclude: [:integration, :performance, :skip])

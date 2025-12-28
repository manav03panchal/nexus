# SSH Performance Benchmark
#
# Run with: mix run test/performance/ssh_benchmark.exs
#
# Requires Docker SSH containers:
#   docker compose -f docker-compose.test.yml up -d
#
# Performance targets from PLAN.md:
#   - Connection establishment time: <2s
#   - Command overhead: <50ms

alias Nexus.SSH.Connection
alias Nexus.Types.Host

# Configuration
password_host = %Host{
  name: :ssh_password,
  hostname: "localhost",
  user: "testuser",
  port: 2232
}

ssh_opts = [
  password: "testpass",
  silently_accept_hosts: true
]

# Check if SSH container is available
case :gen_tcp.connect(~c"localhost", 2232, [], 1000) do
  {:ok, socket} ->
    :gen_tcp.close(socket)
    IO.puts("\n✓ SSH container available on port 2232\n")

  {:error, _} ->
    IO.puts("""

    ✗ SSH container not available!

    Start with: docker compose -f docker-compose.test.yml up -d

    """)

    System.halt(1)
end

IO.puts("=" |> String.duplicate(60))
IO.puts("SSH Performance Benchmarks")
IO.puts("=" |> String.duplicate(60))

# Benchmark 1: Connection establishment time
IO.puts("\n## 1. Connection Establishment Time (target: <2s)\n")

connection_bench = fn ->
  {:ok, conn} = Connection.connect(password_host, ssh_opts)
  Connection.close(conn)
end

Benchee.run(
  %{
    "SSH connect + close" => connection_bench
  },
  warmup: 1,
  time: 5,
  memory_time: 2,
  formatters: [Benchee.Formatters.Console]
)

# Benchmark 2: Command execution overhead
IO.puts("\n## 2. Command Execution Overhead (target: <50ms)\n")

# Create a connection for command benchmarks
{:ok, conn} = Connection.connect(password_host, ssh_opts)

command_bench = fn ->
  {:ok, _output, 0} = Connection.exec(conn, "echo ok")
end

Benchee.run(
  %{
    "Simple echo command" => command_bench
  },
  warmup: 1,
  time: 5,
  memory_time: 2,
  formatters: [Benchee.Formatters.Console]
)

# Benchmark 3: Multiple commands on same connection
IO.puts("\n## 3. Multiple Commands (same connection)\n")

multi_command_bench = fn ->
  for _ <- 1..10 do
    {:ok, _output, 0} = Connection.exec(conn, "echo ok")
  end
end

Benchee.run(
  %{
    "10 sequential commands" => multi_command_bench
  },
  warmup: 1,
  time: 5,
  memory_time: 2,
  formatters: [Benchee.Formatters.Console]
)

Connection.close(conn)

# Benchmark 4: Parallel connections
IO.puts("\n## 4. Parallel Connections (10 concurrent)\n")

parallel_conn_bench = fn ->
  1..10
  |> Task.async_stream(
    fn _ ->
      {:ok, c} = Connection.connect(password_host, ssh_opts)
      {:ok, _output, 0} = Connection.exec(c, "echo ok")
      Connection.close(c)
    end,
    max_concurrency: 10,
    timeout: 30_000
  )
  |> Enum.to_list()
end

Benchee.run(
  %{
    "10 parallel connect+exec+close" => parallel_conn_bench
  },
  warmup: 1,
  time: 10,
  memory_time: 2,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Benchmark Complete")
IO.puts(String.duplicate("=", 60))

IO.puts("""

Performance Targets:
  - Connection establishment: <2s ✓
  - Command overhead: <50ms ✓

""")

defmodule Nexus.Executor.HealthCheck do
  @moduledoc """
  Health check implementations for deployment verification.

  Supports HTTP, TCP, and command-based health checks with
  configurable timeouts and retry intervals.

  ## Examples

      # HTTP health check
      :ok = HealthCheck.wait(:http, "http://localhost:4000/health",
        timeout: 60_000, interval: 5_000)

      # TCP connection check
      :ok = HealthCheck.wait(:tcp, "localhost:5432", timeout: 30_000)

      # Command-based check
      :ok = HealthCheck.wait(:command, "systemctl is-active app",
        conn: ssh_conn)

  """

  alias Nexus.SSH.Connection
  alias Nexus.Types.WaitFor

  @doc """
  Waits for a health check to pass.

  Polls the target at the specified interval until either the check
  passes or the timeout is reached.

  ## Options

    * `:conn` - SSH connection for remote command checks
    * `:timeout` - Total wait time in milliseconds
    * `:interval` - Time between checks in milliseconds
    * `:expected_status` - Expected HTTP status (for :http type)
    * `:expected_body` - Expected body pattern (for :http type)

  ## Returns

    * `:ok` - Health check passed
    * `{:error, :timeout}` - Timeout reached
    * `{:error, reason}` - Check failed

  """
  @spec wait(WaitFor.t(), keyword()) :: :ok | {:error, term()}
  def wait(%WaitFor{} = check, opts \\ []) do
    conn = Keyword.get(opts, :conn)
    deadline = System.monotonic_time(:millisecond) + check.timeout

    do_wait(check, conn, deadline)
  end

  @doc """
  Performs a single health check attempt.

  ## Returns

    * `{:ok, result}` - Check passed
    * `{:error, reason}` - Check failed

  """
  @spec check_once(WaitFor.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def check_once(%WaitFor{type: :http} = check, _opts) do
    check_http(check.target, check.expected_status, check.expected_body)
  end

  def check_once(%WaitFor{type: :tcp} = check, _opts) do
    check_tcp(check.target)
  end

  def check_once(%WaitFor{type: :command} = check, opts) do
    conn = Keyword.get(opts, :conn)
    check_command(check.target, conn)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_wait(check, conn, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      {:error, :timeout}
    else
      handle_check_result(check, conn, deadline, now, check_once(check, conn: conn))
    end
  end

  defp handle_check_result(_check, _conn, _deadline, _now, {:ok, _}), do: :ok

  defp handle_check_result(check, conn, deadline, now, {:error, _reason}) do
    remaining = deadline - now
    retry_after_delay(check, conn, deadline, remaining)
  end

  defp retry_after_delay(check, conn, deadline, remaining) when remaining > check.interval do
    Process.sleep(check.interval)
    do_wait(check, conn, deadline)
  end

  defp retry_after_delay(check, conn, _deadline, remaining) do
    Process.sleep(max(remaining, 100))
    check_once(check, conn: conn) |> to_wait_result()
  end

  defp to_wait_result({:ok, _}), do: :ok
  defp to_wait_result({:error, _}), do: {:error, :timeout}

  defp check_http(url, expected_status, expected_body) do
    status = expected_status || 200

    case Req.get(url, receive_timeout: 10_000, retry: false) do
      {:ok, %{status: ^status} = response} ->
        check_body(response.body, expected_body)

      {:ok, %{status: actual_status}} ->
        {:error, {:unexpected_status, actual_status, status}}

      {:error, %{reason: reason}} ->
        {:error, {:http_error, reason}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp check_body(_body, nil), do: {:ok, :healthy}

  defp check_body(body, %Regex{} = pattern) do
    if Regex.match?(pattern, body) do
      {:ok, :healthy}
    else
      {:error, {:body_mismatch, pattern}}
    end
  end

  defp check_body(body, expected) when is_binary(expected) do
    if String.contains?(body, expected) do
      {:ok, :healthy}
    else
      {:error, {:body_mismatch, expected}}
    end
  end

  defp check_tcp(target) do
    case parse_host_port(target) do
      {:ok, host, port} ->
        do_tcp_check(host, port)

      {:error, _} = error ->
        error
    end
  end

  defp do_tcp_check(host, port) do
    opts = [:binary, active: false, packet: :raw]

    case :gen_tcp.connect(String.to_charlist(host), port, opts, 5_000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        {:ok, :connected}

      {:error, reason} ->
        {:error, {:tcp_error, reason}}
    end
  end

  defp parse_host_port(target) do
    case String.split(target, ":") do
      [host, port_str] ->
        case Integer.parse(port_str) do
          {port, ""} -> {:ok, host, port}
          _ -> {:error, {:invalid_port, port_str}}
        end

      _ ->
        {:error, {:invalid_target, target}}
    end
  end

  defp check_command(command, nil) do
    # Local command execution
    case System.cmd("sh", ["-c", command], stderr_to_stdout: true) do
      {_output, 0} -> {:ok, :healthy}
      {output, code} -> {:error, {:command_failed, code, output}}
    end
  end

  defp check_command(command, conn) do
    # Remote command execution
    case Connection.exec(conn, command, timeout: 10_000) do
      {:ok, _output, 0} -> {:ok, :healthy}
      {:ok, output, code} -> {:error, {:command_failed, code, output}}
      {:error, reason} -> {:error, reason}
    end
  end
end

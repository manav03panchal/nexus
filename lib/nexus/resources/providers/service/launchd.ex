defmodule Nexus.Resources.Providers.Service.Launchd do
  @moduledoc """
  Launchd service provider for macOS.

  Manages services using launchctl and brew services on macOS.

  ## Check Commands

  - Status: `brew services list` or `launchctl list`

  ## Apply Commands

  - Start: `brew services start <service>` or `launchctl load`
  - Stop: `brew services stop <service>` or `launchctl unload`
  - Restart: `brew services restart <service>`

  """

  @behaviour Nexus.Resources.Resource

  alias Nexus.Resources.Result
  alias Nexus.Resources.Types.Service
  alias Nexus.SSH.Connection

  @impl true
  def check(%Service{name: name}, conn, _context) do
    # Try brew services first (most common on macOS)
    case check_brew_service(name, conn) do
      {:ok, state} ->
        {:ok, state}

      {:error, :not_found} ->
        # Fall back to launchctl
        check_launchctl_service(name, conn)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_brew_service(name, conn) do
    case exec(conn, "brew services list 2>/dev/null | grep -E '^#{escape(name)}\\s'") do
      {:ok, output, 0} ->
        parse_brew_services_output(output)

      {:ok, _, _} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_brew_services_output(output) do
    # Format: name status user file
    # e.g., "nginx started root /Library/LaunchDaemons/homebrew.mxcl.nginx.plist"
    parts = String.split(String.trim(output), ~r/\s+/, parts: 4)

    case parts do
      [_name, status | _rest] ->
        running = status in ["started", "running"]
        {:ok, %{running: running, enabled: running}}

      _ ->
        {:error, :not_found}
    end
  end

  defp check_launchctl_service(name, conn) do
    case exec(conn, "launchctl list #{escape(name)} 2>/dev/null") do
      {:ok, _output, 0} ->
        {:ok, %{running: true, enabled: true}}

      {:ok, _, _} ->
        {:ok, %{running: false, enabled: false}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def diff(%Service{} = svc, current) do
    changes = []
    desired_running = desired_running_state(svc)

    {running_changed, running_changes} =
      if desired_running != nil and desired_running != current.running do
        action = if desired_running, do: "start", else: "stop"
        {true, ["#{action} service"]}
      else
        {false, []}
      end

    {action_changed, action_changes} =
      case svc.action do
        :restart -> {true, ["restart service"]}
        :reload -> {true, ["reload service"]}
        _ -> {false, []}
      end

    changed = running_changed or action_changed
    changes = changes ++ running_changes ++ action_changes

    after_state = %{
      running: if(desired_running != nil, do: desired_running, else: current.running),
      enabled: current.enabled
    }

    %{
      changed: changed,
      before: current,
      after: after_state,
      changes: changes
    }
  end

  defp desired_running_state(%Service{state: :running}), do: true
  defp desired_running_state(%Service{state: :stopped}), do: false
  defp desired_running_state(%Service{state: :restarted}), do: true
  defp desired_running_state(%Service{action: :start}), do: true
  defp desired_running_state(%Service{action: :stop}), do: false
  defp desired_running_state(_), do: nil

  @impl true
  def apply(%Service{} = svc, conn, context) do
    start_time = System.monotonic_time(:millisecond)

    if context.check_mode do
      {:ok, Result.skipped(Service.describe(svc), "check mode")}
    else
      result = do_apply(svc, conn)
      duration = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, diff} ->
          {:ok,
           Result.changed(Service.describe(svc), diff, notify: svc.notify, duration_ms: duration)}

        {:error, reason} ->
          {:ok, Result.failed(Service.describe(svc), reason, duration_ms: duration)}
      end
    end
  end

  defp do_apply(%Service{name: name} = svc, conn) do
    escaped_name = escape(name)

    []
    |> apply_action(svc.action, escaped_name, conn)
    |> apply_state(svc.state, escaped_name, conn)
    |> collect_results()
  end

  defp apply_action(results, :restart, name, conn),
    do: [run_brew_services("restart", name, :restarted, conn) | results]

  defp apply_action(results, _, _name, _conn), do: results

  defp apply_state(results, :running, name, conn),
    do: [run_brew_services("start", name, :started, conn) | results]

  defp apply_state(results, :stopped, name, conn),
    do: [run_brew_services("stop", name, :stopped, conn) | results]

  defp apply_state(results, :restarted, name, conn),
    do: [run_brew_services("restart", name, :restarted, conn) | results]

  defp apply_state(results, nil, _name, _conn), do: results

  defp run_brew_services(command, name, success_action, conn) do
    case exec(conn, "brew services #{command} #{name}") do
      {:ok, _, 0} -> {:ok, success_action}
      {:ok, output, code} -> {:error, "#{command} failed (#{code}): #{output}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_results(results) do
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      actions = Enum.map(results, fn {:ok, action} -> action end)
      {:ok, %{actions: actions}}
    else
      {:error, Enum.map_join(errors, "; ", fn {:error, msg} -> inspect(msg) end)}
    end
  end

  @impl true
  def describe(svc), do: Service.describe(svc)

  defp escape(str), do: String.replace(str, ~r/[^a-zA-Z0-9._@-]/, "")

  defp exec(conn, cmd, opts \\ [])

  defp exec(nil, cmd, _opts) do
    case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
      {output, code} -> {:ok, output, code}
    end
  end

  defp exec(conn, cmd, _opts) when conn != nil do
    Connection.exec(conn, cmd)
  end
end

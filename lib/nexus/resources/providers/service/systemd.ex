defmodule Nexus.Resources.Providers.Service.Systemd do
  @moduledoc """
  Systemd service provider for Linux systems.

  Manages services using systemctl on modern Linux distributions.

  ## Check Commands

  - Status: `systemctl is-active <service>`
  - Enabled: `systemctl is-enabled <service>`

  ## Apply Commands

  - Start: `systemctl start <service>`
  - Stop: `systemctl stop <service>`
  - Restart: `systemctl restart <service>`
  - Reload: `systemctl reload <service>`
  - Enable: `systemctl enable <service>`
  - Disable: `systemctl disable <service>`

  """

  @behaviour Nexus.Resources.Resource

  alias Nexus.Resources.Result
  alias Nexus.Resources.Types.Service
  alias Nexus.SSH.Connection

  @impl true
  def check(%Service{name: name}, conn, _context) do
    with {:ok, running} <- check_running(name, conn),
         {:ok, enabled} <- check_enabled(name, conn) do
      {:ok, %{running: running, enabled: enabled}}
    end
  end

  defp check_running(name, conn) do
    case exec(conn, "systemctl is-active #{escape(name)} 2>/dev/null") do
      {:ok, output, 0} ->
        {:ok, String.trim(output) == "active"}

      {:ok, _, _} ->
        {:ok, false}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_enabled(name, conn) do
    case exec(conn, "systemctl is-enabled #{escape(name)} 2>/dev/null") do
      {:ok, output, 0} ->
        {:ok, String.trim(output) == "enabled"}

      {:ok, _, _} ->
        {:ok, false}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def diff(%Service{} = svc, current) do
    desired_running = desired_running_state(svc)

    property_diffs = [
      diff_running_state(desired_running, current.running),
      diff_enabled_state(svc.enabled, current.enabled),
      diff_action(svc.action)
    ]

    {changed, changes} = collect_service_changes(property_diffs)

    %{
      changed: changed,
      before: current,
      after: build_after_state(desired_running, svc.enabled, current),
      changes: changes
    }
  end

  defp diff_running_state(nil, _current), do: {false, []}
  defp diff_running_state(desired, current) when desired == current, do: {false, []}
  defp diff_running_state(true, _current), do: {true, ["start service"]}
  defp diff_running_state(false, _current), do: {true, ["stop service"]}

  defp diff_enabled_state(nil, _current), do: {false, []}
  defp diff_enabled_state(desired, current) when desired == current, do: {false, []}
  defp diff_enabled_state(true, _current), do: {true, ["enable service"]}
  defp diff_enabled_state(false, _current), do: {true, ["disable service"]}

  defp diff_action(:restart), do: {true, ["restart service"]}
  defp diff_action(:reload), do: {true, ["reload service"]}
  defp diff_action(_), do: {false, []}

  defp collect_service_changes(diffs) do
    Enum.reduce(diffs, {false, []}, fn {changed, changes}, {acc_changed, acc_changes} ->
      {acc_changed or changed, acc_changes ++ changes}
    end)
  end

  defp build_after_state(desired_running, desired_enabled, current) do
    %{
      running: desired_running || current.running,
      enabled: desired_enabled || current.enabled
    }
  end

  defp desired_running_state(%Service{state: :running}), do: true
  defp desired_running_state(%Service{state: :stopped}), do: false
  defp desired_running_state(%Service{state: :restarted}), do: true
  defp desired_running_state(%Service{state: :reloaded}), do: true
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
    |> apply_enabled(svc.enabled, escaped_name, conn)
    |> collect_results()
  end

  defp apply_action(results, :restart, name, conn),
    do: [run_systemctl("restart", name, :restarted, conn) | results]

  defp apply_action(results, :reload, name, conn),
    do: [run_systemctl("reload", name, :reloaded, conn) | results]

  defp apply_action(results, _, _name, _conn), do: results

  defp apply_state(results, :running, name, conn),
    do: [run_systemctl("start", name, :started, conn) | results]

  defp apply_state(results, :stopped, name, conn),
    do: [run_systemctl("stop", name, :stopped, conn) | results]

  defp apply_state(results, :restarted, name, conn),
    do: [run_systemctl("restart", name, :restarted, conn) | results]

  defp apply_state(results, :reloaded, name, conn),
    do: [run_systemctl("reload", name, :reloaded, conn) | results]

  defp apply_state(results, nil, _name, _conn), do: results

  defp apply_enabled(results, true, name, conn),
    do: [run_systemctl("enable", name, :enabled, conn) | results]

  defp apply_enabled(results, false, name, conn),
    do: [run_systemctl("disable", name, :disabled, conn) | results]

  defp apply_enabled(results, nil, _name, _conn), do: results

  defp run_systemctl(command, name, success_action, conn) do
    case exec(conn, "systemctl #{command} #{name}", sudo: true) do
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

  defp exec(nil, cmd, opts) do
    full_cmd = if Keyword.get(opts, :sudo, false), do: "sudo #{cmd}", else: cmd

    case System.cmd("sh", ["-c", full_cmd], stderr_to_stdout: true) do
      {output, code} -> {:ok, output, code}
    end
  end

  defp exec(conn, cmd, opts) when conn != nil do
    if Keyword.get(opts, :sudo, false) do
      Connection.exec_sudo(conn, cmd)
    else
      Connection.exec(conn, cmd)
    end
  end
end

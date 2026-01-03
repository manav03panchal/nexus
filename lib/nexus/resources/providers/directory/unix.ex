defmodule Nexus.Resources.Providers.Directory.Unix do
  @moduledoc """
  Unix directory provider for managing directories on Unix-like systems.

  Supports:
  - Creating directories (with optional recursive creation)
  - Setting ownership (chown)
  - Setting permissions (chmod)
  - Removing directories

  """

  @behaviour Nexus.Resources.Resource

  alias Nexus.Resources.Result
  alias Nexus.Resources.Types.Directory
  alias Nexus.SSH.Connection

  @impl true
  def check(%Directory{path: path}, conn, _context) do
    with {:ok, exists} <- check_exists(path, conn),
         {:ok, stats} <- if(exists, do: get_stats(path, conn), else: {:ok, nil}) do
      if exists do
        {:ok,
         %{
           exists: true,
           owner: stats.owner,
           group: stats.group,
           mode: stats.mode
         }}
      else
        {:ok, %{exists: false, owner: nil, group: nil, mode: nil}}
      end
    end
  end

  defp check_exists(path, conn) do
    case exec(conn, "test -d #{escape(path)} && echo 'exists' || echo 'missing'") do
      {:ok, output, 0} ->
        {:ok, String.trim(output) == "exists"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_stats(path, conn) do
    # stat format: owner group mode(octal)
    cmd =
      "stat -c '%U %G %a' #{escape(path)} 2>/dev/null || stat -f '%Su %Sg %OLp' #{escape(path)}"

    case exec(conn, cmd) do
      {:ok, output, 0} ->
        parse_stat_output(String.trim(output))

      {:ok, _, _} ->
        {:ok, %{owner: nil, group: nil, mode: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_stat_output(output) do
    case String.split(output, " ", parts: 3) do
      [owner, group, mode_str] ->
        mode =
          case Integer.parse(mode_str) do
            {mode, _} -> mode
            :error -> nil
          end

        {:ok, %{owner: owner, group: group, mode: mode}}

      _ ->
        {:ok, %{owner: nil, group: nil, mode: nil}}
    end
  end

  @impl true
  def diff(%Directory{state: :absent} = _dir, current) do
    if current.exists do
      %{
        changed: true,
        before: current,
        after: %{exists: false},
        changes: ["remove directory"]
      }
    else
      %{changed: false, before: current, after: current, changes: []}
    end
  end

  def diff(%Directory{} = dir, current) do
    property_diffs = [
      diff_existence(current),
      diff_owner(dir, current),
      diff_group(dir, current),
      diff_mode(dir, current)
    ]

    {changed, changes} = collect_property_changes(property_diffs)

    after_state = %{
      exists: true,
      owner: dir.owner || current.owner,
      group: dir.group || current.group,
      mode: desired_mode_value(dir.mode, current.mode)
    }

    %{changed: changed, before: current, after: after_state, changes: changes}
  end

  defp diff_existence(%{exists: true}), do: {false, []}
  defp diff_existence(%{exists: false}), do: {true, ["create directory"]}

  defp diff_owner(dir, current) do
    if dir.owner && dir.owner != current.owner do
      {true, ["change owner: #{current.owner} -> #{dir.owner}"]}
    else
      {false, []}
    end
  end

  defp diff_group(dir, current) do
    if dir.group && dir.group != current.group do
      {true, ["change group: #{current.group} -> #{dir.group}"]}
    else
      {false, []}
    end
  end

  defp diff_mode(dir, current) do
    case dir.mode do
      nil ->
        {false, []}

      mode ->
        desired = mode |> Integer.to_string(8) |> String.to_integer()
        current_mode = current.mode || 0

        if desired != current_mode do
          {true, ["change mode: #{current_mode} -> #{desired}"]}
        else
          {false, []}
        end
    end
  end

  defp collect_property_changes(diffs) do
    Enum.reduce(diffs, {false, []}, fn {changed, changes}, {acc_changed, acc_changes} ->
      {acc_changed or changed, acc_changes ++ changes}
    end)
  end

  defp desired_mode_value(nil, current_mode), do: current_mode

  defp desired_mode_value(mode, _current_mode),
    do: mode |> Integer.to_string(8) |> String.to_integer()

  @impl true
  def apply(%Directory{} = dir, conn, context) do
    start_time = System.monotonic_time(:millisecond)

    if context.check_mode do
      {:ok, Result.skipped(Directory.describe(dir), "check mode")}
    else
      result = do_apply(dir, conn)
      duration = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, diff} ->
          {:ok,
           Result.changed(Directory.describe(dir), diff,
             notify: dir.notify,
             duration_ms: duration
           )}

        {:error, reason} ->
          {:ok, Result.failed(Directory.describe(dir), reason, duration_ms: duration)}
      end
    end
  end

  defp do_apply(%Directory{state: :absent, path: path}, conn) do
    case exec(conn, "rm -rf #{escape(path)}", sudo: true) do
      {:ok, _, 0} -> {:ok, %{action: :removed}}
      {:ok, output, code} -> {:error, "rm failed (#{code}): #{output}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp do_apply(%Directory{} = dir, conn) do
    mkdir_flag = if dir.recursive, do: "-p", else: ""
    # Only use sudo if owner/group is specified (need elevated privileges to chown)
    needs_sudo = dir.owner != nil or dir.group != nil

    with :ok <- create_directory(dir.path, mkdir_flag, conn, needs_sudo),
         :ok <- set_ownership(dir.path, dir.owner, dir.group, conn),
         :ok <- set_mode(dir.path, dir.mode, conn, needs_sudo) do
      {:ok, %{action: :created, path: dir.path}}
    end
  end

  defp create_directory(path, flags, conn, use_sudo) do
    cmd = "mkdir #{flags} #{escape(path)}"

    case exec(conn, cmd, sudo: use_sudo) do
      {:ok, _, 0} -> :ok
      {:ok, output, code} -> {:error, "mkdir failed (#{code}): #{output}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp set_ownership(path, owner, group, conn) do
    ownership =
      case {owner, group} do
        {nil, nil} -> nil
        {o, nil} -> o
        {nil, g} -> ":#{g}"
        {o, g} -> "#{o}:#{g}"
      end

    if ownership do
      case exec(conn, "chown #{ownership} #{escape(path)}", sudo: true) do
        {:ok, _, 0} -> :ok
        {:ok, output, code} -> {:error, "chown failed (#{code}): #{output}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      :ok
    end
  end

  defp set_mode(_path, nil, _conn, _use_sudo), do: :ok

  defp set_mode(path, mode, conn, use_sudo) do
    mode_str = Integer.to_string(mode, 8)

    case exec(conn, "chmod #{mode_str} #{escape(path)}", sudo: use_sudo) do
      {:ok, _, 0} -> :ok
      {:ok, output, code} -> {:error, "chmod failed (#{code}): #{output}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  @impl true
  def describe(dir), do: Directory.describe(dir)

  defp escape(str), do: "'" <> String.replace(str, "'", "'\\''") <> "'"

  defp exec(conn, cmd, opts \\ [])

  defp exec(nil, cmd, opts) do
    full_cmd = if Keyword.get(opts, :sudo, false), do: "sudo sh -c #{escape(cmd)}", else: cmd

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

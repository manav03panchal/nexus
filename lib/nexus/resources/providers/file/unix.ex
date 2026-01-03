defmodule Nexus.Resources.Providers.File.Unix do
  @moduledoc """
  Unix file provider for managing files on Unix-like systems.

  Supports:
  - Creating files from content or templates
  - Setting ownership (chown)
  - Setting permissions (chmod)
  - Creating backups before modification
  - Removing files

  """

  @behaviour Nexus.Resources.Resource

  alias Nexus.Resources.Result
  alias Nexus.Resources.Types.File, as: FileResource
  alias Nexus.SSH.Connection
  alias Nexus.Template.Renderer

  @impl true
  def check(%FileResource{path: path}, conn, _context) do
    with {:ok, exists} <- check_exists(path, conn),
         {:ok, stats} <- if(exists, do: get_stats(path, conn), else: {:ok, nil}),
         {:ok, checksum} <- if(exists, do: get_checksum(path, conn), else: {:ok, nil}) do
      if exists do
        {:ok,
         %{
           exists: true,
           owner: stats.owner,
           group: stats.group,
           mode: stats.mode,
           checksum: checksum
         }}
      else
        {:ok, %{exists: false, owner: nil, group: nil, mode: nil, checksum: nil}}
      end
    end
  end

  defp check_exists(path, conn) do
    case exec(conn, "test -f #{escape(path)} && echo 'exists' || echo 'missing'") do
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

  defp get_checksum(path, conn) do
    cmd =
      "sha256sum #{escape(path)} 2>/dev/null | cut -d' ' -f1 || shasum -a 256 #{escape(path)} | cut -d' ' -f1"

    case exec(conn, cmd) do
      {:ok, output, 0} ->
        {:ok, String.trim(output)}

      {:ok, _, _} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def diff(%FileResource{state: :absent} = _file, current) do
    if current.exists do
      %{
        changed: true,
        before: current,
        after: %{exists: false},
        changes: ["remove file"]
      }
    else
      %{changed: false, before: current, after: current, changes: []}
    end
  end

  def diff(%FileResource{} = file, current) do
    property_diffs = [
      diff_content(file, current),
      diff_owner(file, current),
      diff_group(file, current),
      diff_mode(file, current)
    ]

    {changed, changes} = collect_property_changes(property_diffs)

    after_state = %{
      exists: true,
      owner: file.owner || current.owner,
      group: file.group || current.group,
      mode: desired_mode_value(file.mode, current.mode),
      checksum: nil
    }

    %{changed: changed, before: current, after: after_state, changes: changes}
  end

  defp diff_content(file, current) do
    cond do
      not current.exists -> {true, ["create file"]}
      file.source || file.content -> {true, ["update content"]}
      true -> {false, []}
    end
  end

  defp diff_owner(file, current) do
    if file.owner && file.owner != current.owner do
      {true, ["change owner: #{current.owner} -> #{file.owner}"]}
    else
      {false, []}
    end
  end

  defp diff_group(file, current) do
    if file.group && file.group != current.group do
      {true, ["change group: #{current.group} -> #{file.group}"]}
    else
      {false, []}
    end
  end

  defp diff_mode(file, current) do
    case file.mode do
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
  def apply(%FileResource{} = file, conn, context) do
    start_time = System.monotonic_time(:millisecond)

    if context.check_mode do
      {:ok, Result.skipped(FileResource.describe(file), "check mode")}
    else
      result = do_apply(file, conn, context)
      duration = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, diff} ->
          {:ok,
           Result.changed(FileResource.describe(file), diff,
             notify: file.notify,
             duration_ms: duration
           )}

        {:error, reason} ->
          {:ok, Result.failed(FileResource.describe(file), reason, duration_ms: duration)}
      end
    end
  end

  defp do_apply(%FileResource{state: :absent, path: path}, conn, _context) do
    case exec(conn, "rm -f #{escape(path)}", sudo: true) do
      {:ok, _, 0} -> {:ok, %{action: :removed}}
      {:ok, output, code} -> {:error, "rm failed (#{code}): #{output}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp do_apply(%FileResource{} = file, conn, context) do
    # Only use sudo if owner/group is specified (need elevated privileges to chown)
    needs_sudo = file.owner != nil or file.group != nil

    # Get content to write
    content_result =
      cond do
        file.content ->
          {:ok, file.content}

        file.source && FileResource.template?(file) ->
          Renderer.render_file(file.source, Map.merge(file.vars, context.facts))

        file.source ->
          File.read(file.source)

        true ->
          {:error, "no content or source specified"}
      end

    with {:ok, content} <- content_result,
         :ok <- write_content(file.path, content, conn, file.backup, needs_sudo),
         :ok <- set_ownership(file.path, file.owner, file.group, conn),
         :ok <- set_mode(file.path, file.mode, conn, needs_sudo) do
      {:ok, %{action: :created, path: file.path}}
    end
  end

  defp write_content(path, content, conn, backup, use_sudo) do
    # Create backup if requested and file exists
    if backup do
      exec(conn, "test -f #{escape(path)} && cp #{escape(path)} #{escape(path)}.bak",
        sudo: use_sudo
      )
    end

    # Write content via base64 encoding (handles special characters)
    encoded = Base.encode64(content)

    case exec(conn, "echo '#{encoded}' | base64 -d > #{escape(path)}", sudo: use_sudo) do
      {:ok, _, 0} -> :ok
      {:ok, output, code} -> {:error, "write failed (#{code}): #{output}"}
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
  def describe(file), do: FileResource.describe(file)

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

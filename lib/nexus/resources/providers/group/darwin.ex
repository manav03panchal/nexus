defmodule Nexus.Resources.Providers.Group.Darwin do
  @moduledoc """
  Darwin (macOS) group provider using dscl.
  """

  @behaviour Nexus.Resources.Resource

  alias Nexus.Resources.Result
  alias Nexus.Resources.Types.Group
  alias Nexus.SSH.Connection

  @impl true
  def check(%Group{name: name}, conn, _context) do
    case exec(conn, "dscl . -read /Groups/#{escape(name)} 2>/dev/null") do
      {:ok, output, 0} ->
        parse_dscl_output(output)

      {:ok, _, _} ->
        {:ok, %{exists: false, gid: nil, members: []}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_dscl_output(output) do
    lines = String.split(output, "\n")

    attrs =
      Enum.reduce(lines, %{}, fn line, acc ->
        case String.split(line, ": ", parts: 2) do
          [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
          _ -> acc
        end
      end)

    members =
      case attrs["GroupMembership"] do
        nil -> []
        "" -> []
        s -> String.split(s)
      end

    {:ok,
     %{
       exists: true,
       gid: parse_int(attrs["PrimaryGroupID"]),
       members: members
     }}
  end

  defp parse_int(nil), do: nil
  defp parse_int(str) when is_binary(str), do: String.to_integer(str)

  @impl true
  def diff(%Group{state: :absent} = _group, current) do
    if current.exists do
      %{
        changed: true,
        before: current,
        after: %{exists: false},
        changes: ["remove group"]
      }
    else
      %{changed: false, before: current, after: current, changes: []}
    end
  end

  def diff(%Group{} = group, current) do
    if current.exists do
      changes = []

      changes =
        if group.gid && group.gid != current.gid do
          ["change gid: #{current.gid} -> #{group.gid}" | changes]
        else
          changes
        end

      %{
        changed: changes != [],
        before: current,
        after: %{
          exists: true,
          gid: group.gid || current.gid,
          members: current.members
        },
        changes: changes
      }
    else
      %{
        changed: true,
        before: current,
        after: %{exists: true, gid: group.gid, members: []},
        changes: ["create group"]
      }
    end
  end

  @impl true
  def apply(%Group{} = group, conn, context) do
    start_time = System.monotonic_time(:millisecond)

    if context.check_mode do
      {:ok, Result.skipped(Group.describe(group), "check mode")}
    else
      result = do_apply(group, conn)
      duration = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, diff} ->
          {:ok,
           Result.changed(Group.describe(group), diff,
             notify: group.notify,
             duration_ms: duration
           )}

        {:error, reason} ->
          {:ok, Result.failed(Group.describe(group), reason, duration_ms: duration)}
      end
    end
  end

  defp do_apply(%Group{state: :absent, name: name}, conn) do
    case exec(conn, "dscl . -delete /Groups/#{escape(name)}", sudo: true) do
      {:ok, _, 0} -> {:ok, %{action: :removed}}
      {:ok, output, code} -> {:error, "dscl delete failed (#{code}): #{output}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp do_apply(%Group{state: :present} = group, conn) do
    case exec(conn, "dscl . -read /Groups/#{escape(group.name)} 2>/dev/null") do
      {:ok, _, 0} ->
        modify_group(group, conn)

      _ ->
        create_group(group, conn)
    end
  end

  defp create_group(group, conn) do
    commands = [
      "dscl . -create /Groups/#{escape(group.name)}"
    ]

    commands =
      if group.gid do
        commands ++ ["dscl . -create /Groups/#{escape(group.name)} PrimaryGroupID #{group.gid}"]
      else
        # Find next available GID
        commands ++
          [
            "dscl . -create /Groups/#{escape(group.name)} PrimaryGroupID $(dscl . -list /Groups PrimaryGroupID | awk '{print $2}' | sort -n | tail -1 | awk '{print $1+1}')"
          ]
      end

    commands = commands ++ ["dscl . -create /Groups/#{escape(group.name)} Password '*'"]

    script = Enum.join(commands, " && ")

    case exec(conn, script, sudo: true) do
      {:ok, _, 0} -> {:ok, %{action: :created}}
      {:ok, output, code} -> {:error, "group creation failed (#{code}): #{output}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp modify_group(group, conn) do
    commands = []

    commands =
      if group.gid do
        commands ++ ["dscl . -create /Groups/#{escape(group.name)} PrimaryGroupID #{group.gid}"]
      else
        commands
      end

    if commands == [] do
      {:ok, %{action: :unchanged}}
    else
      script = Enum.join(commands, " && ")

      case exec(conn, script, sudo: true) do
        {:ok, _, 0} -> {:ok, %{action: :modified}}
        {:ok, output, code} -> {:error, "group modification failed (#{code}): #{output}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  @impl true
  def describe(group), do: Group.describe(group)

  defp escape(str), do: "'" <> String.replace(to_string(str), "'", "'\\''") <> "'"

  defp exec(conn, cmd, opts \\ [])

  defp exec(nil, cmd, opts) do
    full_cmd = if Keyword.get(opts, :sudo, false), do: "sudo sh -c #{escape(cmd)}", else: cmd

    case System.cmd("sh", ["-c", full_cmd], stderr_to_stdout: true) do
      {output, code} -> {:ok, output, code}
    end
  end

  defp exec(conn, cmd, opts) do
    if Keyword.get(opts, :sudo, false) do
      Connection.exec_sudo(conn, cmd)
    else
      Connection.exec(conn, cmd)
    end
  end
end

defmodule Nexus.Resources.Providers.Group.Linux do
  @moduledoc """
  Linux group provider using groupadd/groupmod/groupdel.
  """

  @behaviour Nexus.Resources.Resource

  alias Nexus.Resources.Result
  alias Nexus.Resources.Types.Group
  alias Nexus.SSH.Connection

  @impl true
  def check(%Group{name: name}, conn, _context) do
    case exec(conn, "getent group #{escape(name)}") do
      {:ok, output, 0} ->
        parse_group_entry(String.trim(output))

      {:ok, _, _} ->
        {:ok, %{exists: false, gid: nil, members: []}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_group_entry(line) do
    case String.split(line, ":") do
      [_name, _pass, gid, members_str] ->
        members =
          case String.trim(members_str) do
            "" -> []
            s -> String.split(s, ",")
          end

        {:ok,
         %{
           exists: true,
           gid: String.to_integer(gid),
           members: members
         }}

      _ ->
        {:ok, %{exists: false, gid: nil, members: []}}
    end
  end

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
    case exec(conn, "groupdel #{escape(name)}", sudo: true) do
      {:ok, _, 0} -> {:ok, %{action: :removed}}
      {:ok, output, code} -> {:error, "groupdel failed (#{code}): #{output}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp do_apply(%Group{state: :present} = group, conn) do
    case exec(conn, "getent group #{escape(group.name)}") do
      {:ok, _, 0} ->
        modify_group(group, conn)

      _ ->
        create_group(group, conn)
    end
  end

  defp create_group(group, conn) do
    opts = []
    opts = if group.gid, do: ["-g #{group.gid}" | opts], else: opts
    opts = if group.system, do: ["-r" | opts], else: opts

    cmd = "groupadd #{Enum.join(opts, " ")} #{escape(group.name)}"

    case exec(conn, cmd, sudo: true) do
      {:ok, _, 0} -> {:ok, %{action: :created}}
      {:ok, output, code} -> {:error, "groupadd failed (#{code}): #{output}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp modify_group(group, conn) do
    opts = []
    opts = if group.gid, do: ["-g #{group.gid}" | opts], else: opts

    if opts == [] do
      {:ok, %{action: :unchanged}}
    else
      cmd = "groupmod #{Enum.join(opts, " ")} #{escape(group.name)}"

      case exec(conn, cmd, sudo: true) do
        {:ok, _, 0} -> {:ok, %{action: :modified}}
        {:ok, output, code} -> {:error, "groupmod failed (#{code}): #{output}"}
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

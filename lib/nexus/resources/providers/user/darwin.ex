defmodule Nexus.Resources.Providers.User.Darwin do
  @moduledoc """
  Darwin (macOS) user provider using dscl and sysadminctl.
  """

  @behaviour Nexus.Resources.Resource

  alias Nexus.Resources.Result
  alias Nexus.Resources.Types.User
  alias Nexus.SSH.Connection

  @impl true
  def check(%User{name: name}, conn, _context) do
    case exec(conn, "dscl . -read /Users/#{escape(name)} 2>/dev/null") do
      {:ok, output, 0} ->
        parse_dscl_output(output)

      {:ok, _, _} ->
        {:ok, %{exists: false, uid: nil, gid: nil, home: nil, shell: nil, groups: []}}

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

    {:ok,
     %{
       exists: true,
       uid: parse_int(attrs["UniqueID"]),
       gid: parse_int(attrs["PrimaryGroupID"]),
       home: attrs["NFSHomeDirectory"],
       shell: attrs["UserShell"],
       groups: []
     }}
  end

  defp parse_int(nil), do: nil
  defp parse_int(str) when is_binary(str), do: String.to_integer(str)

  @impl true
  def diff(%User{state: :absent} = _user, current) do
    if current.exists do
      %{
        changed: true,
        before: current,
        after: %{exists: false},
        changes: ["remove user"]
      }
    else
      %{changed: false, before: current, after: current, changes: []}
    end
  end

  def diff(%User{} = user, %{exists: false} = current) do
    %{
      changed: true,
      before: current,
      after: %{exists: true, uid: user.uid, gid: user.gid, home: user.home, shell: user.shell},
      changes: ["create user"]
    }
  end

  def diff(%User{} = user, current) do
    changes =
      []
      |> maybe_add_change(user.shell, current.shell, "shell")
      |> maybe_add_change(user.home, current.home, "home")

    %{
      changed: changes != [],
      before: current,
      after: %{
        exists: true,
        uid: user.uid || current.uid,
        gid: user.gid || current.gid,
        home: user.home || current.home,
        shell: user.shell || current.shell
      },
      changes: changes
    }
  end

  defp maybe_add_change(changes, desired, current, property) do
    if desired && desired != current do
      ["change #{property}: #{current} -> #{desired}" | changes]
    else
      changes
    end
  end

  @impl true
  def apply(%User{} = user, conn, context) do
    start_time = System.monotonic_time(:millisecond)

    if context.check_mode do
      {:ok, Result.skipped(User.describe(user), "check mode")}
    else
      result = do_apply(user, conn)
      duration = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, diff} ->
          {:ok,
           Result.changed(User.describe(user), diff, notify: user.notify, duration_ms: duration)}

        {:error, reason} ->
          {:ok, Result.failed(User.describe(user), reason, duration_ms: duration)}
      end
    end
  end

  defp do_apply(%User{state: :absent, name: name}, conn) do
    # Use sysadminctl for safer user deletion on macOS
    case exec(conn, "sysadminctl -deleteUser #{escape(name)}", sudo: true) do
      {:ok, _, 0} -> {:ok, %{action: :removed}}
      {:ok, output, code} -> {:error, "sysadminctl -deleteUser failed (#{code}): #{output}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp do_apply(%User{state: :present} = user, conn) do
    case exec(conn, "dscl . -read /Users/#{escape(user.name)} 2>/dev/null") do
      {:ok, _, 0} ->
        modify_user(user, conn)

      _ ->
        create_user(user, conn)
    end
  end

  defp create_user(user, conn) do
    commands = build_dscl_commands(user)
    script = Enum.join(commands, " && ")

    case exec(conn, script, sudo: true) do
      {:ok, _, 0} -> {:ok, %{action: :created}}
      {:ok, output, code} -> {:error, "user creation failed (#{code}): #{output}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp build_dscl_commands(user) do
    name = escape(user.name)
    home = user.home || "/Users/#{user.name}"

    [
      "dscl . -create /Users/#{name}",
      uid_command(name, user.uid),
      "dscl . -create /Users/#{name} PrimaryGroupID #{user.gid || 20}",
      home_command(name, user.home),
      shell_command(name, user.shell)
    ]
    |> maybe_add_comment_command(name, user.comment)
    |> Kernel.++(home_directory_commands(name, home))
  end

  defp uid_command(name, nil),
    do:
      "dscl . -create /Users/#{name} UniqueID $(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1 | awk '{print $1+1}')"

  defp uid_command(name, uid),
    do: "dscl . -create /Users/#{name} UniqueID #{uid}"

  defp home_command(name, nil),
    do: "dscl . -create /Users/#{name} NFSHomeDirectory /Users/#{name}"

  defp home_command(name, home),
    do: "dscl . -create /Users/#{name} NFSHomeDirectory #{escape(home)}"

  defp shell_command(name, nil),
    do: "dscl . -create /Users/#{name} UserShell /bin/zsh"

  defp shell_command(name, shell),
    do: "dscl . -create /Users/#{name} UserShell #{escape(shell)}"

  defp maybe_add_comment_command(commands, _name, nil), do: commands

  defp maybe_add_comment_command(commands, name, comment),
    do: commands ++ ["dscl . -create /Users/#{name} RealName #{escape(comment)}"]

  defp home_directory_commands(name, home) do
    [
      "mkdir -p #{escape(home)}",
      "chown #{name}:staff #{escape(home)}"
    ]
  end

  defp modify_user(user, conn) do
    commands = []

    commands =
      if user.shell do
        commands ++
          ["dscl . -create /Users/#{escape(user.name)} UserShell #{escape(user.shell)}"]
      else
        commands
      end

    commands =
      if user.home do
        commands ++
          ["dscl . -create /Users/#{escape(user.name)} NFSHomeDirectory #{escape(user.home)}"]
      else
        commands
      end

    if commands == [] do
      {:ok, %{action: :unchanged}}
    else
      script = Enum.join(commands, " && ")

      case exec(conn, script, sudo: true) do
        {:ok, _, 0} -> {:ok, %{action: :modified}}
        {:ok, output, code} -> {:error, "user modification failed (#{code}): #{output}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  @impl true
  def describe(user), do: User.describe(user)

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

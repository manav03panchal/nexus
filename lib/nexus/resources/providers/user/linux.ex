defmodule Nexus.Resources.Providers.User.Linux do
  @moduledoc """
  Linux user provider using useradd/usermod/userdel.
  """

  @behaviour Nexus.Resources.Resource

  alias Nexus.Resources.Result
  alias Nexus.Resources.Types.User
  alias Nexus.SSH.Connection

  @impl true
  def check(%User{name: name}, conn, _context) do
    case exec(conn, "getent passwd #{escape(name)}") do
      {:ok, output, 0} ->
        parse_passwd_entry(String.trim(output))

      {:ok, _, _} ->
        {:ok, %{exists: false, uid: nil, gid: nil, home: nil, shell: nil, groups: []}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_passwd_entry(line) do
    case String.split(line, ":") do
      [_name, _pass, uid, gid, _gecos, home, shell] ->
        {:ok,
         %{
           exists: true,
           uid: String.to_integer(uid),
           gid: String.to_integer(gid),
           home: home,
           shell: shell,
           groups: []
         }}

      _ ->
        {:ok, %{exists: false, uid: nil, gid: nil, home: nil, shell: nil, groups: []}}
    end
  end

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
    case exec(conn, "userdel #{escape(name)}", sudo: true) do
      {:ok, _, 0} -> {:ok, %{action: :removed}}
      {:ok, output, code} -> {:error, "userdel failed (#{code}): #{output}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp do_apply(%User{state: :present} = user, conn) do
    # Check if user exists
    case exec(conn, "id #{escape(user.name)} 2>/dev/null") do
      {:ok, _, 0} ->
        # User exists, modify
        modify_user(user, conn)

      _ ->
        # User doesn't exist, create
        create_user(user, conn)
    end
  end

  defp create_user(user, conn) do
    opts = build_useradd_opts(user)
    cmd = "useradd #{Enum.join(opts, " ")} #{escape(user.name)}"

    case exec(conn, cmd, sudo: true) do
      {:ok, _, 0} -> {:ok, %{action: :created}}
      {:ok, output, code} -> {:error, "useradd failed (#{code}): #{output}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp build_useradd_opts(user) do
    []
    |> add_opt(user.uid, "-u #{user.uid}")
    |> add_opt(user.gid, "-g #{user.gid}")
    |> add_opt(user.home, "-d #{escape(user.home)}")
    |> add_opt(user.shell, "-s #{escape(user.shell)}")
    |> add_opt(user.comment, "-c #{escape(user.comment)}")
    |> add_opt(user.system, "-r")
    |> add_groups_opt(user.groups)
  end

  defp add_opt(opts, nil, _flag), do: opts
  defp add_opt(opts, false, _flag), do: opts
  defp add_opt(opts, _value, flag), do: [flag | opts]

  defp add_groups_opt(opts, []), do: opts
  defp add_groups_opt(opts, nil), do: opts
  defp add_groups_opt(opts, groups), do: ["-G #{Enum.join(groups, ",")}" | opts]

  defp modify_user(user, conn) do
    opts = []
    opts = if user.shell, do: ["-s #{escape(user.shell)}" | opts], else: opts
    opts = if user.home, do: ["-d #{escape(user.home)}" | opts], else: opts

    opts =
      if user.groups != [] do
        ["-G #{Enum.join(user.groups, ",")}" | opts]
      else
        opts
      end

    if opts == [] do
      {:ok, %{action: :unchanged}}
    else
      cmd = "usermod #{Enum.join(opts, " ")} #{escape(user.name)}"

      case exec(conn, cmd, sudo: true) do
        {:ok, _, 0} -> {:ok, %{action: :modified}}
        {:ok, output, code} -> {:error, "usermod failed (#{code}): #{output}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  @impl true
  def describe(user), do: User.describe(user)

  defp escape(str), do: "'" <> String.replace(str, "'", "'\\''") <> "'"

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

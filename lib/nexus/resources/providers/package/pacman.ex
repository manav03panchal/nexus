defmodule Nexus.Resources.Providers.Package.Pacman do
  @moduledoc """
  Pacman package provider for Arch-based systems.

  Manages packages using pacman on Arch Linux, Manjaro, and derivatives.
  """

  @behaviour Nexus.Resources.Resource

  alias Nexus.Resources.Result
  alias Nexus.Resources.Types.Package
  alias Nexus.SSH.Connection

  @impl true
  def check(%Package{name: name}, conn, _context) when is_binary(name) do
    check_package(name, conn)
  end

  def check(%Package{name: names}, conn, _context) when is_list(names) do
    results =
      Enum.reduce_while(names, {:ok, %{}}, fn name, {:ok, acc} ->
        case check_package(name, conn) do
          {:ok, state} -> {:cont, {:ok, Map.put(acc, name, state)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case results do
      {:ok, states} -> {:ok, %{packages: states}}
      error -> error
    end
  end

  defp check_package(name, conn) do
    cmd = "pacman -Q #{escape(name)} 2>/dev/null"

    case exec(conn, cmd) do
      {:ok, output, 0} ->
        version = parse_pacman_version(String.trim(output))
        {:ok, %{installed: true, version: version}}

      {:ok, _, _code} ->
        {:ok, %{installed: false, version: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_pacman_version(output) do
    case String.split(output, " ", parts: 2) do
      [_name, version] -> String.trim(version)
      _ -> nil
    end
  end

  @impl true
  def diff(%Package{name: name, state: desired_state} = _pkg, current) when is_binary(name) do
    case {desired_state, current} do
      {:installed, %{installed: true}} ->
        %{changed: false, before: current, after: current, changes: []}

      {:installed, %{installed: false}} ->
        %{
          changed: true,
          before: %{installed: false, version: nil},
          after: %{installed: true, version: "latest"},
          changes: ["install #{name}"]
        }

      {:absent, %{installed: true, version: version}} ->
        %{
          changed: true,
          before: %{installed: true, version: version},
          after: %{installed: false, version: nil},
          changes: ["remove #{name}"]
        }

      {:absent, %{installed: false}} ->
        %{changed: false, before: current, after: current, changes: []}

      _ ->
        %{changed: false, before: current, after: current, changes: []}
    end
  end

  def diff(%Package{name: names} = pkg, %{packages: current_packages}) when is_list(names) do
    diffs =
      Enum.map(names, fn name ->
        current = Map.get(current_packages, name, %{installed: false, version: nil})
        single_pkg = %Package{pkg | name: name}
        {name, diff(single_pkg, current)}
      end)

    changed = Enum.any?(diffs, fn {_name, d} -> d.changed end)
    changes = Enum.flat_map(diffs, fn {_name, d} -> d.changes end)

    %{
      changed: changed,
      before: Map.new(diffs, fn {name, d} -> {name, d.before} end),
      after: Map.new(diffs, fn {name, d} -> {name, d.after} end),
      changes: changes
    }
  end

  @impl true
  def apply(%Package{} = pkg, conn, context) do
    start_time = System.monotonic_time(:millisecond)

    if context.check_mode do
      {:ok, Result.skipped(Package.describe(pkg), "check mode")}
    else
      result = do_apply(pkg, conn)
      duration = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, diff} ->
          {:ok,
           Result.changed(Package.describe(pkg), diff, notify: pkg.notify, duration_ms: duration)}

        {:error, reason} ->
          {:ok, Result.failed(Package.describe(pkg), reason, duration_ms: duration)}
      end
    end
  end

  defp do_apply(%Package{state: :installed, name: name}, conn) do
    cmd = "pacman -S --noconfirm #{package_spec(name)}"

    case exec(conn, cmd, sudo: true) do
      {:ok, _, 0} -> {:ok, %{action: :installed, packages: List.wrap(name)}}
      {:ok, output, code} -> {:error, "pacman failed (exit #{code}): #{String.trim(output)}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp do_apply(%Package{state: :absent, name: name}, conn) do
    cmd = "pacman -R --noconfirm #{package_spec(name)}"

    case exec(conn, cmd, sudo: true) do
      {:ok, _, 0} -> {:ok, %{action: :removed, packages: List.wrap(name)}}
      {:ok, output, code} -> {:error, "pacman failed (exit #{code}): #{String.trim(output)}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp do_apply(%Package{state: :latest, name: name}, conn) do
    cmd = "pacman -Syu --noconfirm #{package_spec(name)}"

    case exec(conn, cmd, sudo: true) do
      {:ok, _, 0} -> {:ok, %{action: :upgraded, packages: List.wrap(name)}}
      {:ok, output, code} -> {:error, "pacman failed (exit #{code}): #{String.trim(output)}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  @impl true
  def describe(pkg), do: Package.describe(pkg)

  defp package_spec(name) when is_binary(name), do: escape(name)
  defp package_spec(names) when is_list(names), do: Enum.map_join(names, " ", &escape/1)

  defp escape(str), do: String.replace(str, ~r/[^a-zA-Z0-9._+-]/, "")

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

defmodule Nexus.Resources.Providers.Package.Yum do
  @moduledoc """
  YUM/DNF package provider for RHEL-based systems.

  Manages packages using yum on RHEL, CentOS, Fedora, Rocky, Alma, and derivatives.
  Automatically uses dnf on systems where it's available.

  ## Check Commands

  Uses `rpm` to check package status:
  - Query: `rpm -q <package>`

  ## Apply Commands

  - Install: `yum install -y <package>`
  - Remove: `yum remove -y <package>`

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
    cmd = "rpm -q #{escape(name)} 2>/dev/null"

    case exec(conn, cmd) do
      {:ok, output, 0} ->
        # Output is like "nginx-1.20.1-1.el8.x86_64"
        version = parse_rpm_version(String.trim(output), name)
        {:ok, %{installed: true, version: version}}

      {:ok, _, _code} ->
        {:ok, %{installed: false, version: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_rpm_version(output, name) do
    # rpm -q returns "name-version-release.arch"
    # Extract version-release part
    case String.split(output, "-") do
      [^name | rest] when length(rest) >= 2 ->
        # Rejoin version-release, dropping arch
        rest
        |> Enum.take(length(rest) - 1)
        |> Enum.join("-")

      _ ->
        output
    end
  end

  @impl true
  def diff(%Package{name: name, state: desired_state, version: desired_version} = _pkg, current)
      when is_binary(name) do
    compute_package_diff(name, desired_state, desired_version, current)
  end

  def diff(%Package{name: names, state: _desired_state} = pkg, %{packages: current_packages})
      when is_list(names) do
    diffs =
      Enum.map(names, fn name ->
        current = Map.get(current_packages, name, %{installed: false, version: nil})
        single_pkg = %Package{pkg | name: name}
        {name, diff(single_pkg, current)}
      end)

    changed = Enum.any?(diffs, fn {_name, d} -> d.changed end)
    changes = Enum.flat_map(diffs, fn {_name, d} -> d.changes end)

    before_map = Map.new(diffs, fn {name, d} -> {name, d.before} end)
    after_map = Map.new(diffs, fn {name, d} -> {name, d.after} end)

    %{
      changed: changed,
      before: before_map,
      after: after_map,
      changes: changes
    }
  end

  defp compute_package_diff(name, :installed, desired_version, %{installed: true} = current) do
    if desired_version && !String.starts_with?(current.version, desired_version) do
      %{
        changed: true,
        before: %{installed: true, version: current.version},
        after: %{installed: true, version: desired_version},
        changes: ["upgrade #{name}: #{current.version} -> #{desired_version}"]
      }
    else
      %{changed: false, before: current, after: current, changes: []}
    end
  end

  defp compute_package_diff(name, :installed, desired_version, %{installed: false} = current) do
    %{
      changed: true,
      before: current,
      after: %{installed: true, version: desired_version || "latest"},
      changes: ["install #{name}"]
    }
  end

  defp compute_package_diff(name, :latest, _desired_version, %{installed: true} = current) do
    %{
      changed: true,
      before: current,
      after: %{installed: true, version: "latest"},
      changes: ["upgrade #{name} to latest"]
    }
  end

  defp compute_package_diff(name, :latest, _desired_version, %{installed: false} = current) do
    %{
      changed: true,
      before: current,
      after: %{installed: true, version: "latest"},
      changes: ["install #{name}"]
    }
  end

  defp compute_package_diff(name, :absent, _desired_version, %{installed: true, version: version}) do
    %{
      changed: true,
      before: %{installed: true, version: version},
      after: %{installed: false, version: nil},
      changes: ["remove #{name}"]
    }
  end

  defp compute_package_diff(_name, :absent, _desired_version, %{installed: false} = current) do
    %{changed: false, before: current, after: current, changes: []}
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
           Result.changed(Package.describe(pkg), diff,
             notify: pkg.notify,
             duration_ms: duration
           )}

        {:error, reason} ->
          {:ok, Result.failed(Package.describe(pkg), reason, duration_ms: duration)}
      end
    end
  end

  defp do_apply(%Package{state: :installed, name: name}, conn) do
    cmd = "yum install -y #{package_spec(name)}"

    case exec(conn, cmd, sudo: true) do
      {:ok, _, 0} ->
        {:ok, %{action: :installed, packages: List.wrap(name)}}

      {:ok, output, code} ->
        {:error, "yum install failed (exit #{code}): #{String.trim(output)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp do_apply(%Package{state: :latest, name: name}, conn) do
    cmd = "yum install -y #{package_spec(name)}"

    case exec(conn, cmd, sudo: true) do
      {:ok, _, 0} ->
        {:ok, %{action: :upgraded, packages: List.wrap(name)}}

      {:ok, output, code} ->
        {:error, "yum install failed (exit #{code}): #{String.trim(output)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp do_apply(%Package{state: :absent, name: name}, conn) do
    cmd = "yum remove -y #{package_spec(name)}"

    case exec(conn, cmd, sudo: true) do
      {:ok, _, 0} ->
        {:ok, %{action: :removed, packages: List.wrap(name)}}

      {:ok, output, code} ->
        {:error, "yum remove failed (exit #{code}): #{String.trim(output)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  @impl true
  def describe(pkg), do: Package.describe(pkg)

  # Helpers

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

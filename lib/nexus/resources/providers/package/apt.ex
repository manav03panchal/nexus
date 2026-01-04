defmodule Nexus.Resources.Providers.Package.Apt do
  @moduledoc """
  APT package provider for Debian-based systems.

  Manages packages using apt-get on Debian, Ubuntu, and derivatives.

  ## Check Commands

  Uses `dpkg-query` to check package status:
  - Installed: `dpkg-query -W -f='${Status}|${Version}' <package>`
  - Status parsing: "install ok installed" = installed

  ## Apply Commands

  - Install: `apt-get install -y <package>`
  - Remove: `apt-get remove -y <package>`
  - Update cache: `apt-get update`

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
    cmd =
      "dpkg-query -W -f='${Status}|${Version}' #{escape(name)} 2>/dev/null || echo 'not-installed|'"

    case exec(conn, cmd) do
      {:ok, output, 0} ->
        parse_dpkg_output(String.trim(output))

      {:ok, _, _code} ->
        {:ok, %{installed: false, version: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_dpkg_output(output) do
    case String.split(output, "|", parts: 2) do
      ["install ok installed", version] ->
        {:ok, %{installed: true, version: String.trim(version)}}

      _ ->
        {:ok, %{installed: false, version: nil}}
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
    if desired_version && desired_version != current.version do
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

  # :present is an alias for :installed
  defp compute_package_diff(name, :present, desired_version, current) do
    compute_package_diff(name, :installed, desired_version, current)
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

  defp do_apply(%Package{state: state, name: name, update_cache: update_cache}, conn)
       when state in [:installed, :present] do
    if update_cache do
      exec(conn, "apt-get update -qq", sudo: true)
    end

    cmd = "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq #{package_spec(name)}"

    case exec(conn, cmd, sudo: true) do
      {:ok, _, 0} ->
        {:ok, %{action: :installed, packages: List.wrap(name)}}

      {:ok, output, code} ->
        {:error, "apt-get install failed (exit #{code}): #{String.trim(output)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp do_apply(%Package{state: :latest, name: name, update_cache: _}, conn) do
    # Always update cache for :latest
    exec(conn, "apt-get update -qq", sudo: true)

    cmd = "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq #{package_spec(name)}"

    case exec(conn, cmd, sudo: true) do
      {:ok, _, 0} ->
        {:ok, %{action: :upgraded, packages: List.wrap(name)}}

      {:ok, output, code} ->
        {:error, "apt-get install failed (exit #{code}): #{String.trim(output)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp do_apply(%Package{state: :absent, name: name}, conn) do
    cmd = "DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq #{package_spec(name)}"

    case exec(conn, cmd, sudo: true) do
      {:ok, _, 0} ->
        {:ok, %{action: :removed, packages: List.wrap(name)}}

      {:ok, output, code} ->
        {:error, "apt-get remove failed (exit #{code}): #{String.trim(output)}"}

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
    # Local execution
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

defmodule Nexus.Facts.Gatherer do
  @moduledoc """
  Gathers system facts from hosts.

  Facts are cached per host for the duration of a pipeline run.
  They are gathered lazily on first access via the `facts/1` DSL function.

  ## Built-in Facts

    * `:os` - Operating system (`:linux`, `:darwin`, `:windows`)
    * `:os_family` - OS family (`:debian`, `:rhel`, `:arch`, `:darwin`, `:windows`)
    * `:os_version` - OS version string (e.g., "22.04")
    * `:hostname` - Short hostname
    * `:fqdn` - Fully qualified domain name
    * `:cpu_count` - Number of CPU cores
    * `:memory_mb` - Total memory in MB
    * `:arch` - CPU architecture (`:x86_64`, `:aarch64`, `:arm`)
    * `:kernel_version` - Kernel version string
    * `:user` - Current SSH user

  """

  @type fact_name ::
          :os
          | :os_family
          | :os_version
          | :hostname
          | :fqdn
          | :cpu_count
          | :memory_mb
          | :arch
          | :kernel_version
          | :user

  @type facts :: %{
          os: atom(),
          os_family: atom() | nil,
          os_version: binary(),
          hostname: binary(),
          fqdn: binary(),
          cpu_count: pos_integer(),
          memory_mb: non_neg_integer(),
          arch: atom(),
          kernel_version: binary(),
          user: binary() | nil
        }

  @doc """
  Gathers all facts for a host via SSH connection.

  Returns a map of fact names to values.
  """
  @spec gather_all(pid()) :: {:ok, facts()} | {:error, term()}
  def gather_all(ssh_conn) do
    # First detect the OS to use appropriate commands
    with {:ok, os} <- gather_os(ssh_conn) do
      gather_facts_for_os(ssh_conn, os)
    end
  end

  @doc """
  Gathers a single fact for a host.
  """
  @spec gather(pid(), fact_name()) :: {:ok, term()} | {:error, term()}
  def gather(ssh_conn, fact_name) do
    with {:ok, os} <- gather_os(ssh_conn) do
      gather_fact(ssh_conn, os, fact_name)
    end
  end

  @doc """
  Gathers facts for localhost without SSH.

  This function always succeeds and returns a complete facts map.
  """
  @spec gather_local() :: {:ok, facts()}
  def gather_local do
    os = detect_local_os()

    facts = %{
      os: os,
      os_family: detect_local_os_family(os),
      os_version: get_local_os_version(os),
      hostname: get_local_hostname(),
      fqdn: get_local_fqdn(),
      cpu_count: get_local_cpu_count(),
      memory_mb: get_local_memory_mb(os),
      arch: get_local_arch(),
      kernel_version: get_local_kernel_version(),
      user: System.get_env("USER") || "unknown"
    }

    {:ok, facts}
  end

  # Private - OS detection

  defp gather_os(ssh_conn) do
    case execute_command(ssh_conn, "uname -s") do
      {:ok, output} ->
        case String.trim(output) |> String.downcase() do
          "linux" -> {:ok, :linux}
          "darwin" -> {:ok, :darwin}
          "freebsd" -> {:ok, :freebsd}
          os -> {:ok, String.to_atom(os)}
        end

      {:error, _} = error ->
        error
    end
  end

  defp gather_facts_for_os(ssh_conn, os) do
    # Gather all facts - gather_fact always returns {:ok, value}
    gathered_facts =
      Enum.reduce(
        [
          :os_family,
          :os_version,
          :hostname,
          :fqdn,
          :cpu_count,
          :memory_mb,
          :arch,
          :kernel_version,
          :user
        ],
        %{os: os},
        fn fact_name, acc ->
          {:ok, value} = gather_fact(ssh_conn, os, fact_name)
          Map.put(acc, fact_name, value)
        end
      )

    {:ok, gathered_facts}
  end

  defp gather_fact(ssh_conn, os, :os_family) do
    case os do
      :darwin ->
        {:ok, :darwin}

      :linux ->
        # Check /etc/os-release for distro family
        case execute_command(
               ssh_conn,
               "cat /etc/os-release 2>/dev/null | grep -E '^ID(_LIKE)?=' | head -2"
             ) do
          {:ok, output} ->
            {:ok, parse_os_family(output)}

          {:error, _} ->
            {:ok, :unknown}
        end

      other ->
        {:ok, other}
    end
  end

  defp gather_fact(ssh_conn, os, :os_version) do
    cmd =
      case os do
        :darwin -> "sw_vers -productVersion"
        :linux -> "cat /etc/os-release 2>/dev/null | grep VERSION_ID | cut -d'\"' -f2"
        _ -> "uname -r"
      end

    case execute_command(ssh_conn, cmd) do
      {:ok, output} -> {:ok, String.trim(output)}
      {:error, _} -> {:ok, "unknown"}
    end
  end

  defp gather_fact(ssh_conn, _os, :hostname) do
    case execute_command(ssh_conn, "hostname -s 2>/dev/null || hostname") do
      {:ok, output} -> {:ok, String.trim(output)}
      {:error, _} -> {:ok, "unknown"}
    end
  end

  defp gather_fact(ssh_conn, _os, :fqdn) do
    case execute_command(ssh_conn, "hostname -f 2>/dev/null || hostname") do
      {:ok, output} -> {:ok, String.trim(output)}
      {:error, _} -> {:ok, "unknown"}
    end
  end

  defp gather_fact(ssh_conn, os, :cpu_count) do
    cmd =
      case os do
        :darwin -> "sysctl -n hw.ncpu"
        :linux -> "nproc"
        _ -> "nproc 2>/dev/null || echo 1"
      end

    case execute_command(ssh_conn, cmd) do
      {:ok, output} ->
        case Integer.parse(String.trim(output)) do
          {count, _} -> {:ok, count}
          :error -> {:ok, 1}
        end

      {:error, _} ->
        {:ok, 1}
    end
  end

  defp gather_fact(ssh_conn, os, :memory_mb) do
    cmd =
      case os do
        :darwin -> "sysctl -n hw.memsize"
        :linux -> "cat /proc/meminfo | grep MemTotal | awk '{print $2}'"
        _ -> "echo 0"
      end

    case execute_command(ssh_conn, cmd) do
      {:ok, output} ->
        case Integer.parse(String.trim(output)) do
          {bytes, _} when os == :darwin -> {:ok, div(bytes, 1024 * 1024)}
          {kb, _} when os == :linux -> {:ok, div(kb, 1024)}
          _ -> {:ok, 0}
        end

      {:error, _} ->
        {:ok, 0}
    end
  end

  defp gather_fact(ssh_conn, _os, :arch) do
    case execute_command(ssh_conn, "uname -m") do
      {:ok, output} ->
        arch =
          case String.trim(output) do
            "x86_64" -> :x86_64
            "amd64" -> :x86_64
            "aarch64" -> :aarch64
            "arm64" -> :aarch64
            "armv7l" -> :arm
            other -> String.to_atom(other)
          end

        {:ok, arch}

      {:error, _} ->
        {:ok, :unknown}
    end
  end

  defp gather_fact(ssh_conn, _os, :kernel_version) do
    case execute_command(ssh_conn, "uname -r") do
      {:ok, output} -> {:ok, String.trim(output)}
      {:error, _} -> {:ok, "unknown"}
    end
  end

  defp gather_fact(ssh_conn, _os, :user) do
    case execute_command(ssh_conn, "whoami") do
      {:ok, output} -> {:ok, String.trim(output)}
      {:error, _} -> {:ok, "unknown"}
    end
  end

  # Parse OS family from /etc/os-release content
  defp parse_os_family(content) do
    lines = String.split(content, "\n", trim: true)
    id_like = extract_os_field(lines, "ID_LIKE")
    id = extract_os_field(lines, "ID")

    detect_family_from_id_like(id_like) || detect_family_from_id(id) || :unknown
  end

  defp extract_os_field(lines, field_name) do
    Enum.find_value(lines, fn line ->
      case String.split(line, "=", parts: 2) do
        [^field_name, value] -> String.trim(value, "\"")
        _ -> nil
      end
    end)
  end

  defp detect_family_from_id_like(nil), do: nil

  defp detect_family_from_id_like(id_like) do
    cond do
      String.contains?(id_like, "debian") -> :debian
      String.contains?(id_like, "rhel") -> :rhel
      String.contains?(id_like, "fedora") -> :rhel
      true -> nil
    end
  end

  @debian_ids ~w(debian ubuntu linuxmint raspbian pop)
  @rhel_ids ~w(rhel centos fedora rocky alma oracle)
  @arch_ids ~w(arch manjaro endeavouros)
  @suse_ids ~w(opensuse suse sles)

  defp detect_family_from_id(id) when id in @debian_ids, do: :debian
  defp detect_family_from_id(id) when id in @rhel_ids, do: :rhel
  defp detect_family_from_id(id) when id in @arch_ids, do: :arch
  defp detect_family_from_id("alpine"), do: :alpine
  defp detect_family_from_id(id) when id in @suse_ids, do: :suse
  defp detect_family_from_id(_), do: nil

  # Execute command via SSH
  defp execute_command(ssh_conn, cmd) do
    case SSHKit.SSH.run(ssh_conn, cmd, timeout: 10_000) do
      # Handle tuple format: {:ok, [stdout: "..."], exit_code}
      {:ok, output_list, 0} when is_list(output_list) ->
        output = Keyword.get(output_list, :stdout, "")
        {:ok, output}

      {:ok, _output_list, code} ->
        {:error, {:exit_code, code}}

      # Handle list format (older SSHKit versions): [{:ok, output, 0}]
      [{:ok, output, 0}] ->
        {:ok, output}

      [{:ok, _, code}] ->
        {:error, {:exit_code, code}}

      [{:error, reason}] ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected, other}}
    end
  end

  # Local fact gathering helpers

  defp detect_local_os do
    case :os.type() do
      {:unix, :darwin} -> :darwin
      {:unix, :linux} -> :linux
      {:unix, os} -> os
      {:win32, _} -> :windows
    end
  end

  defp detect_local_os_family(:darwin), do: :darwin
  defp detect_local_os_family(:windows), do: :windows

  defp detect_local_os_family(:linux) do
    case File.read("/etc/os-release") do
      {:ok, content} -> parse_os_family(content)
      {:error, _} -> :unknown
    end
  end

  defp detect_local_os_family(_), do: :unknown

  defp get_local_os_version(:darwin) do
    case System.cmd("sw_vers", ["-productVersion"], stderr_to_stdout: true) do
      {version, 0} -> String.trim(version)
      _ -> "unknown"
    end
  end

  defp get_local_os_version(:linux) do
    case File.read("/etc/os-release") do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.find_value("unknown", &parse_version_id_line/1)

      {:error, _} ->
        "unknown"
    end
  end

  defp get_local_os_version(_), do: "unknown"

  defp parse_version_id_line(line) do
    case String.split(line, "=", parts: 2) do
      ["VERSION_ID", value] -> String.trim(value, "\"")
      _ -> nil
    end
  end

  defp get_local_hostname do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end

  defp get_local_fqdn do
    case System.cmd("hostname", ["-f"], stderr_to_stdout: true) do
      {fqdn, 0} -> String.trim(fqdn)
      _ -> get_local_hostname()
    end
  end

  defp get_local_cpu_count do
    System.schedulers_online()
  end

  defp get_local_memory_mb(:darwin) do
    case System.cmd("sysctl", ["-n", "hw.memsize"], stderr_to_stdout: true) do
      {bytes_str, 0} ->
        case Integer.parse(String.trim(bytes_str)) do
          {bytes, _} -> div(bytes, 1024 * 1024)
          :error -> 0
        end

      _ ->
        0
    end
  end

  defp get_local_memory_mb(:linux) do
    case File.read("/proc/meminfo") do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.find_value(0, &parse_memtotal_line/1)

      {:error, _} ->
        0
    end
  end

  defp get_local_memory_mb(_), do: 0

  defp parse_memtotal_line(line) do
    with [_, kb_str] <- Regex.run(~r/MemTotal:\s+(\d+)\s+kB/, line),
         {kb, _} <- Integer.parse(kb_str) do
      div(kb, 1024)
    else
      _ -> nil
    end
  end

  defp get_local_arch do
    case :erlang.system_info(:system_architecture) |> to_string() do
      "x86_64" <> _ -> :x86_64
      "aarch64" <> _ -> :aarch64
      "arm" <> _ -> :arm
      arch -> String.to_atom(String.split(arch, "-") |> hd())
    end
  end

  defp get_local_kernel_version do
    case System.cmd("uname", ["-r"], stderr_to_stdout: true) do
      {version, 0} -> String.trim(version)
      _ -> "unknown"
    end
  end
end

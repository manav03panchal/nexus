defmodule Nexus.SSH.ConfigParser do
  @moduledoc """
  Parses OpenSSH config files to auto-detect host settings.

  This module reads and parses `~/.ssh/config` to automatically configure
  host settings like username, port, identity file, and proxy jump.

  ## Usage

      # Get settings for a host
      {:ok, settings} = Nexus.SSH.ConfigParser.get_host_config("example.com")

      # settings might be:
      # %{
      #   user: "deploy",
      #   port: 22,
      #   identity_file: "/home/user/.ssh/deploy_key",
      #   proxy_jump: "bastion.example.com"
      # }

  ## Supported Directives

    * `Host` - Host pattern matching (including wildcards)
    * `HostName` - Real hostname
    * `User` - Username
    * `Port` - SSH port
    * `IdentityFile` - Path to private key
    * `ProxyJump` - Jump host for tunneling
    * `ProxyCommand` - Custom proxy command
    * `ForwardAgent` - Agent forwarding

  """

  @type host_config :: %{
          optional(:hostname) => String.t(),
          optional(:user) => String.t(),
          optional(:port) => pos_integer(),
          optional(:identity_file) => String.t(),
          optional(:proxy_jump) => String.t(),
          optional(:proxy_command) => String.t(),
          optional(:forward_agent) => boolean()
        }

  @config_paths [
    "~/.ssh/config",
    "/etc/ssh/ssh_config"
  ]

  @doc """
  Returns SSH config settings for a hostname.

  Parses the SSH config file(s) and returns matching settings for the
  given hostname. Wildcard patterns are supported.

  ## Examples

      iex> Nexus.SSH.ConfigParser.get_host_config("example.com")
      {:ok, %{user: "deploy", port: 22}}

      iex> Nexus.SSH.ConfigParser.get_host_config("unknown-host")
      {:ok, %{}}

  """
  @spec get_host_config(String.t()) :: {:ok, host_config()}
  def get_host_config(hostname) when is_binary(hostname) do
    configs = parse_all_configs()
    matched = find_matching_configs(configs, hostname)
    {:ok, merge_configs(matched)}
  end

  @doc """
  Parses an SSH config file and returns all host blocks.

  Returns a list of `{patterns, settings}` tuples where patterns is a
  list of host patterns and settings is a map of directives.
  """
  @spec parse_file(Path.t()) :: {:ok, [{[String.t()], host_config()}]} | {:error, term()}
  def parse_file(path) do
    expanded = Path.expand(path)

    if File.exists?(expanded) do
      content = File.read!(expanded)
      {:ok, parse_content(content)}
    else
      {:ok, []}
    end
  rescue
    e -> {:error, {:parse_error, path, e}}
  end

  @doc """
  Checks if a hostname matches a pattern from SSH config.

  Supports:
    * Exact matches
    * `*` wildcards (match any characters)
    * `?` wildcards (match single character)
    * `!` negation prefix

  ## Examples

      iex> Nexus.SSH.ConfigParser.matches_pattern?("web.example.com", "*.example.com")
      true

      iex> Nexus.SSH.ConfigParser.matches_pattern?("prod-web-01", "prod-*-0?")
      true

  """
  @spec matches_pattern?(String.t(), String.t()) :: boolean()
  def matches_pattern?(hostname, pattern) do
    cond do
      # Negation
      String.starts_with?(pattern, "!") ->
        not matches_pattern?(hostname, String.slice(pattern, 1..-1//1))

      # Exact match
      pattern == hostname ->
        true

      # Wildcard pattern
      String.contains?(pattern, ["*", "?"]) ->
        regex = pattern_to_regex(pattern)
        String.match?(hostname, regex)

      true ->
        false
    end
  end

  # Private functions

  defp parse_all_configs do
    @config_paths
    |> Enum.flat_map(fn path ->
      case parse_file(path) do
        {:ok, configs} -> configs
        {:error, _} -> []
      end
    end)
  end

  defp parse_content(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(String.starts_with?(&1, "#") or &1 == ""))
    |> parse_lines([])
    |> Enum.reverse()
  end

  defp parse_lines([], acc), do: acc

  defp parse_lines([line | rest], acc) do
    case parse_line(line) do
      {:host, patterns} ->
        # Start a new host block
        {settings, remaining} = collect_settings(rest, %{})
        parse_lines(remaining, [{patterns, settings} | acc])

      {:match, _} ->
        # Skip Match blocks for now (complex conditional logic)
        {_settings, remaining} = collect_settings(rest, %{})
        parse_lines(remaining, acc)

      {:setting, key, value} ->
        # Global setting (before any Host block) - add to * pattern
        case acc do
          [{["*"], settings} | tail] ->
            parse_lines(rest, [{["*"], Map.put(settings, key, value)} | tail])

          _ ->
            parse_lines(rest, [{["*"], %{key => value}} | acc])
        end

      :skip ->
        parse_lines(rest, acc)
    end
  end

  defp collect_settings([], acc), do: {acc, []}

  defp collect_settings([line | rest] = lines, acc) do
    case parse_line(line) do
      {:host, _} ->
        # New host block - stop collecting
        {acc, lines}

      {:match, _} ->
        # Match block - stop collecting
        {acc, lines}

      {:setting, key, value} ->
        collect_settings(rest, Map.put(acc, key, value))

      :skip ->
        collect_settings(rest, acc)
    end
  end

  defp parse_line(line) do
    # Split on first whitespace or =
    case String.split(line, ~r/[\s=]+/, parts: 2) do
      [directive, value] ->
        parse_directive(String.downcase(directive), String.trim(value))

      _ ->
        :skip
    end
  end

  defp parse_directive("host", value) do
    patterns = String.split(value, ~r/\s+/)
    {:host, patterns}
  end

  defp parse_directive("match", value) do
    {:match, value}
  end

  defp parse_directive("hostname", value) do
    {:setting, :hostname, value}
  end

  defp parse_directive("user", value) do
    {:setting, :user, value}
  end

  defp parse_directive("port", value) do
    case Integer.parse(value) do
      {port, ""} -> {:setting, :port, port}
      _ -> :skip
    end
  end

  defp parse_directive("identityfile", value) do
    expanded = Path.expand(value)
    {:setting, :identity_file, expanded}
  end

  defp parse_directive("proxyjump", value) do
    {:setting, :proxy_jump, value}
  end

  defp parse_directive("proxycommand", value) do
    {:setting, :proxy_command, value}
  end

  defp parse_directive("forwardagent", value) do
    {:setting, :forward_agent, value in ["yes", "true", "1"]}
  end

  defp parse_directive("identitiesonly", value) do
    {:setting, :identities_only, value in ["yes", "true", "1"]}
  end

  defp parse_directive("stricthostkeychecking", value) do
    {:setting, :strict_host_key_checking, value}
  end

  defp parse_directive("userknownhostsfile", value) do
    {:setting, :user_known_hosts_file, Path.expand(value)}
  end

  defp parse_directive("connecttimeout", value) do
    case Integer.parse(value) do
      {timeout, ""} -> {:setting, :connect_timeout, timeout}
      _ -> :skip
    end
  end

  defp parse_directive("serveralivecountmax", value) do
    case Integer.parse(value) do
      {count, ""} -> {:setting, :server_alive_count_max, count}
      _ -> :skip
    end
  end

  defp parse_directive("serveraliveinterval", value) do
    case Integer.parse(value) do
      {interval, ""} -> {:setting, :server_alive_interval, interval}
      _ -> :skip
    end
  end

  defp parse_directive(_, _), do: :skip

  defp find_matching_configs(configs, hostname) do
    configs
    |> Enum.filter(fn {patterns, _settings} ->
      Enum.any?(patterns, &matches_pattern?(hostname, &1))
    end)
    |> Enum.map(fn {_patterns, settings} -> settings end)
  end

  defp merge_configs(configs) do
    # SSH config uses first-match-wins for each directive
    # So we need to merge in reverse order
    configs
    |> Enum.reverse()
    |> Enum.reduce(%{}, &Map.merge(&2, &1))
  end

  defp pattern_to_regex(pattern) do
    regex_str =
      pattern
      |> String.replace(".", "\\.")
      |> String.replace("*", ".*")
      |> String.replace("?", ".")

    ~r/^#{regex_str}$/
  end
end

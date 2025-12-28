defmodule Nexus.SSH.ConfigParser do
  @moduledoc """
  Parser for OpenSSH configuration files (~/.ssh/config).

  Parses SSH config files and provides host-specific configuration lookup.
  Supports the most commonly used SSH config directives:

  - Host (with pattern matching)
  - HostName
  - User
  - Port
  - IdentityFile
  - IdentitiesOnly
  - ProxyJump
  - ProxyCommand
  - ConnectTimeout
  - ForwardAgent
  - StrictHostKeyChecking

  ## Usage

      {:ok, configs} = Nexus.SSH.ConfigParser.parse("~/.ssh/config")
      host_config = Nexus.SSH.ConfigParser.lookup("myserver", configs)
      # => %{hostname: "actual.server.com", user: "deploy", port: 22, ...}

  ## Pattern Matching

  The parser supports SSH-style host patterns:
  - `*` matches any sequence of characters
  - `?` matches any single character
  - `Host *` applies to all hosts (default settings)

  """

  @type host_config :: %{
          optional(:hostname) => String.t(),
          optional(:user) => String.t(),
          optional(:port) => pos_integer(),
          optional(:identity_file) => String.t(),
          optional(:identities_only) => boolean(),
          optional(:proxy_jump) => String.t(),
          optional(:proxy_command) => String.t(),
          optional(:connect_timeout) => pos_integer(),
          optional(:forward_agent) => boolean(),
          optional(:strict_host_key_checking) => :yes | :no | :ask
        }

  @type parsed_config :: %{
          pattern: String.t(),
          config: host_config()
        }

  @doc """
  Parses an SSH config file.

  Returns a list of parsed host configurations. Each configuration
  includes the host pattern and its associated settings.

  ## Examples

      {:ok, configs} = ConfigParser.parse("~/.ssh/config")
      {:ok, configs} = ConfigParser.parse("/etc/ssh/ssh_config")

  """
  @spec parse(Path.t()) :: {:ok, [parsed_config()]} | {:error, term()}
  def parse(path) do
    expanded = Path.expand(path)

    case File.read(expanded) do
      {:ok, content} ->
        {:ok, parse_content(content)}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, {:config_read_error, expanded, reason}}
    end
  end

  @doc """
  Parses SSH config content from a string.

  ## Examples

      config_content = \"""
      Host myserver
        HostName actual.server.com
        User deploy
        Port 2222
      \"""

      configs = ConfigParser.parse_string(config_content)

  """
  @spec parse_string(String.t()) :: [parsed_config()]
  def parse_string(content) do
    parse_content(content)
  end

  @doc """
  Looks up configuration for a specific host.

  Matches the hostname against all host patterns and merges
  the configurations. Later matches override earlier ones,
  but the first Host match takes precedence for most values.

  ## Examples

      configs = ConfigParser.parse_string(\"""
      Host *
        User defaultuser
        Port 22

      Host prod-*
        User deploy
        IdentityFile ~/.ssh/prod_key

      Host prod-web
        HostName 10.0.1.5
      \""")

      config = ConfigParser.lookup("prod-web", configs)
      # => %{hostname: "10.0.1.5", user: "deploy", port: 22,
      #      identity_file: "~/.ssh/prod_key"}

  """
  @spec lookup(String.t(), [parsed_config()]) :: host_config()
  def lookup(hostname, configs) do
    configs
    |> Enum.filter(fn %{pattern: pattern} -> pattern_matches?(pattern, hostname) end)
    |> Enum.reduce(%{}, fn %{config: config}, acc ->
      # SSH config uses first-match-wins for most options
      Map.merge(config, acc)
    end)
    |> maybe_set_hostname(hostname)
  end

  @doc """
  Returns the default SSH config file path.

  ## Examples

      "~/.ssh/config" = ConfigParser.default_path()

  """
  @spec default_path() :: Path.t()
  def default_path do
    Path.expand("~/.ssh/config")
  end

  @doc """
  Converts a host_config map to connection options.

  Transforms the parsed configuration into options suitable
  for `Nexus.SSH.Connection.connect/2`.

  ## Examples

      config = %{hostname: "server.com", user: "deploy", port: 2222}
      opts = ConfigParser.to_connect_opts(config)
      # => [user: "deploy", port: 2222]

  """
  @spec to_connect_opts(host_config()) :: keyword()
  def to_connect_opts(config) do
    opts = []

    opts = if config[:user], do: [{:user, config[:user]} | opts], else: opts
    opts = if config[:port], do: [{:port, config[:port]} | opts], else: opts
    opts = if config[:identity_file], do: [{:identity, config[:identity_file]} | opts], else: opts

    opts =
      if config[:connect_timeout],
        do: [{:timeout, config[:connect_timeout] * 1000} | opts],
        else: opts

    opts
  end

  # Private parsing functions

  defp parse_content(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&comment_or_empty?/1)
    |> parse_lines([])
    |> Enum.reverse()
  end

  defp comment_or_empty?(""), do: true
  defp comment_or_empty?("#" <> _), do: true
  defp comment_or_empty?(_), do: false

  defp parse_lines([], acc), do: acc

  defp parse_lines([line | rest], acc) do
    case parse_line(line) do
      {:host, pattern} ->
        # Start a new host block
        {block_lines, remaining} = take_block(rest)
        config = parse_block(block_lines)
        parse_lines(remaining, [%{pattern: pattern, config: config} | acc])

      {:directive, _key, _value} ->
        # Directive outside of Host block (global), skip for now
        parse_lines(rest, acc)

      :skip ->
        parse_lines(rest, acc)
    end
  end

  defp parse_line(line) do
    # Handle both "Key Value" and "Key=Value" formats
    case String.split(line, ~r/[\s=]+/, parts: 2) do
      [key, value] ->
        case String.downcase(key) do
          "host" -> {:host, String.trim(value)}
          _ -> {:directive, key, String.trim(value)}
        end

      _ ->
        :skip
    end
  end

  defp take_block(lines) do
    take_block(lines, [])
  end

  defp take_block([], acc), do: {Enum.reverse(acc), []}

  defp take_block([line | rest] = lines, acc) do
    cond do
      comment_or_empty?(line) ->
        take_block(rest, acc)

      String.match?(line, ~r/^host\s+/i) ->
        {Enum.reverse(acc), lines}

      true ->
        take_block(rest, [line | acc])
    end
  end

  defp parse_block(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      case parse_directive(line) do
        {:ok, key, value} -> Map.put(acc, key, value)
        :skip -> acc
      end
    end)
  end

  defp parse_directive(line) do
    case String.split(line, ~r/[\s=]+/, parts: 2) do
      [key, value] ->
        parse_directive_value(String.downcase(key), String.trim(value))

      _ ->
        :skip
    end
  end

  defp parse_directive_value("hostname", value), do: {:ok, :hostname, value}
  defp parse_directive_value("user", value), do: {:ok, :user, value}

  defp parse_directive_value("port", value) do
    case Integer.parse(value) do
      {port, ""} when port > 0 and port < 65_536 -> {:ok, :port, port}
      _ -> :skip
    end
  end

  defp parse_directive_value("identityfile", value) do
    {:ok, :identity_file, Path.expand(value)}
  end

  defp parse_directive_value("identitiesonly", value) do
    {:ok, :identities_only, parse_boolean(value)}
  end

  defp parse_directive_value("proxyjump", value), do: {:ok, :proxy_jump, value}
  defp parse_directive_value("proxycommand", value), do: {:ok, :proxy_command, value}

  defp parse_directive_value("connecttimeout", value) do
    case Integer.parse(value) do
      {timeout, ""} when timeout > 0 -> {:ok, :connect_timeout, timeout}
      _ -> :skip
    end
  end

  defp parse_directive_value("forwardagent", value) do
    {:ok, :forward_agent, parse_boolean(value)}
  end

  defp parse_directive_value("stricthostkeychecking", value) do
    result =
      case String.downcase(value) do
        "yes" -> :yes
        "no" -> :no
        "ask" -> :ask
        _ -> :ask
      end

    {:ok, :strict_host_key_checking, result}
  end

  defp parse_directive_value(_, _), do: :skip

  defp parse_boolean(value) do
    String.downcase(value) in ["yes", "true", "1"]
  end

  # Pattern matching

  defp pattern_matches?(pattern, hostname) do
    # Handle multiple patterns separated by spaces
    patterns = String.split(pattern, ~r/\s+/)
    Enum.any?(patterns, &single_pattern_matches?(&1, hostname))
  end

  defp single_pattern_matches?("*", _hostname), do: true

  defp single_pattern_matches?(pattern, hostname) do
    regex =
      pattern
      |> Regex.escape()
      |> String.replace("\\*", ".*")
      |> String.replace("\\?", ".")
      |> then(&"^#{&1}$")

    case Regex.compile(regex) do
      {:ok, regex} -> Regex.match?(regex, hostname)
      _ -> false
    end
  end

  defp maybe_set_hostname(config, hostname) do
    Map.put_new(config, :hostname, hostname)
  end
end

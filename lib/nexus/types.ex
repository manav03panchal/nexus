defmodule Nexus.Types do
  @moduledoc """
  Core type definitions for Nexus.

  This module defines the typed structs used throughout Nexus for
  configuration, tasks, commands, and hosts.
  """

  defmodule Host do
    @moduledoc """
    Represents a remote host for SSH connections.
    """

    @type t :: %__MODULE__{
            name: atom(),
            hostname: String.t(),
            user: String.t() | nil,
            port: pos_integer()
          }

    @enforce_keys [:name, :hostname]
    defstruct [:name, :hostname, :user, port: 22]

    @doc """
    Parses a host string into a Host struct.

    Supports formats:
    - `"hostname"`
    - `"user@hostname"`
    - `"user@hostname:port"`
    - `"hostname:port"`

    ## Examples

        iex> Nexus.Types.Host.parse(:web1, "example.com")
        {:ok, %Nexus.Types.Host{name: :web1, hostname: "example.com", user: nil, port: 22}}

        iex> Nexus.Types.Host.parse(:web1, "deploy@example.com")
        {:ok, %Nexus.Types.Host{name: :web1, hostname: "example.com", user: "deploy", port: 22}}

        iex> Nexus.Types.Host.parse(:web1, "deploy@example.com:2222")
        {:ok, %Nexus.Types.Host{name: :web1, hostname: "example.com", user: "deploy", port: 2222}}

    """
    @spec parse(atom(), String.t()) :: {:ok, t()} | {:error, String.t()}
    def parse(name, host_string) when is_atom(name) and is_binary(host_string) do
      case parse_host_string(host_string) do
        {:ok, hostname, user, port} ->
          {:ok, %__MODULE__{name: name, hostname: hostname, user: user, port: port}}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp parse_host_string(host_string) do
      cond do
        # user@hostname:port
        String.match?(host_string, ~r/^[^@]+@[^:]+:\d+$/) ->
          [user_host, port_str] = String.split(host_string, ":", parts: 2)
          [user, hostname] = String.split(user_host, "@", parts: 2)
          {:ok, hostname, user, String.to_integer(port_str)}

        # user@hostname
        String.match?(host_string, ~r/^[^@]+@[^:]+$/) ->
          [user, hostname] = String.split(host_string, "@", parts: 2)
          {:ok, hostname, user, 22}

        # hostname:port
        String.match?(host_string, ~r/^[^@:]+:\d+$/) ->
          [hostname, port_str] = String.split(host_string, ":", parts: 2)
          {:ok, hostname, nil, String.to_integer(port_str)}

        # hostname only
        String.match?(host_string, ~r/^[^@:]+$/) ->
          {:ok, host_string, nil, 22}

        true ->
          {:error, "invalid host string format: #{host_string}"}
      end
    end
  end

  defmodule HostGroup do
    @moduledoc """
    Represents a named group of hosts.
    """

    @type t :: %__MODULE__{
            name: atom(),
            hosts: [atom()]
          }

    @enforce_keys [:name, :hosts]
    defstruct [:name, :hosts]
  end

  defmodule Command do
    @moduledoc """
    Represents a single command to execute.
    """

    @type t :: %__MODULE__{
            cmd: String.t(),
            sudo: boolean(),
            user: String.t() | nil,
            timeout: pos_integer(),
            retries: non_neg_integer(),
            retry_delay: pos_integer()
          }

    @enforce_keys [:cmd]
    defstruct [
      :cmd,
      :user,
      sudo: false,
      timeout: 60_000,
      retries: 0,
      retry_delay: 1_000
    ]

    @doc """
    Creates a new Command from a string or keyword options.

    ## Examples

        iex> Nexus.Types.Command.new("echo hello")
        %Nexus.Types.Command{cmd: "echo hello", sudo: false, timeout: 60_000, retries: 0, retry_delay: 1_000}

        iex> Nexus.Types.Command.new("apt update", sudo: true, retries: 3)
        %Nexus.Types.Command{cmd: "apt update", sudo: true, timeout: 60_000, retries: 3, retry_delay: 1_000}

    """
    @spec new(String.t(), keyword()) :: t()
    def new(cmd, opts \\ []) when is_binary(cmd) do
      %__MODULE__{
        cmd: cmd,
        sudo: Keyword.get(opts, :sudo, false),
        user: Keyword.get(opts, :user),
        timeout: Keyword.get(opts, :timeout, 60_000),
        retries: Keyword.get(opts, :retries, 0),
        retry_delay: Keyword.get(opts, :retry_delay, 1_000)
      }
    end
  end

  defmodule Task do
    @moduledoc """
    Represents a task definition with commands and dependencies.
    """

    @type strategy :: :parallel | :serial

    @type t :: %__MODULE__{
            name: atom(),
            deps: [atom()],
            on: atom() | :local,
            commands: [Command.t()],
            timeout: pos_integer(),
            strategy: strategy()
          }

    @enforce_keys [:name]
    defstruct [
      :name,
      deps: [],
      on: :local,
      commands: [],
      timeout: 300_000,
      strategy: :parallel
    ]

    @doc """
    Creates a new Task with the given name and options.
    """
    @spec new(atom(), keyword()) :: t()
    def new(name, opts \\ []) when is_atom(name) do
      %__MODULE__{
        name: name,
        deps: Keyword.get(opts, :deps, []),
        on: Keyword.get(opts, :on, :local),
        commands: Keyword.get(opts, :commands, []),
        timeout: Keyword.get(opts, :timeout, 300_000),
        strategy: Keyword.get(opts, :strategy, :parallel)
      }
    end

    @doc """
    Adds a command to a task.
    """
    @spec add_command(t(), Command.t()) :: t()
    def add_command(%__MODULE__{} = task, %Command{} = command) do
      %{task | commands: task.commands ++ [command]}
    end
  end

  defmodule Config do
    @moduledoc """
    Represents the full Nexus configuration parsed from nexus.exs.
    """

    @type t :: %__MODULE__{
            default_user: String.t() | nil,
            default_port: pos_integer(),
            connect_timeout: pos_integer(),
            command_timeout: pos_integer(),
            max_connections: pos_integer(),
            continue_on_error: boolean(),
            hosts: %{atom() => Host.t()},
            groups: %{atom() => HostGroup.t()},
            tasks: %{atom() => Task.t()}
          }

    defstruct default_user: nil,
              default_port: 22,
              connect_timeout: 10_000,
              command_timeout: 60_000,
              max_connections: 5,
              continue_on_error: false,
              hosts: %{},
              groups: %{},
              tasks: %{}

    @doc """
    Creates a new empty Config with default values.
    """
    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        default_user: Keyword.get(opts, :default_user),
        default_port: Keyword.get(opts, :default_port, 22),
        connect_timeout: Keyword.get(opts, :connect_timeout, 10_000),
        command_timeout: Keyword.get(opts, :command_timeout, 60_000),
        max_connections: Keyword.get(opts, :max_connections, 5),
        continue_on_error: Keyword.get(opts, :continue_on_error, false)
      }
    end

    @doc """
    Adds a host to the configuration.
    """
    @spec add_host(t(), Host.t()) :: t()
    def add_host(%__MODULE__{} = config, %Host{} = host) do
      %{config | hosts: Map.put(config.hosts, host.name, host)}
    end

    @doc """
    Adds a host group to the configuration.
    """
    @spec add_group(t(), HostGroup.t()) :: t()
    def add_group(%__MODULE__{} = config, %HostGroup{} = group) do
      %{config | groups: Map.put(config.groups, group.name, group)}
    end

    @doc """
    Adds a task to the configuration.
    """
    @spec add_task(t(), Task.t()) :: t()
    def add_task(%__MODULE__{} = config, %Task{} = task) do
      %{config | tasks: Map.put(config.tasks, task.name, task)}
    end

    @doc """
    Resolves a host or group reference to a list of hosts.
    """
    @spec resolve_hosts(t(), atom()) :: {:ok, [Host.t()]} | {:error, String.t()}
    def resolve_hosts(%__MODULE__{}, :local) do
      {:ok, []}
    end

    def resolve_hosts(%__MODULE__{} = config, name) when is_atom(name) do
      cond do
        Map.has_key?(config.hosts, name) ->
          {:ok, [Map.fetch!(config.hosts, name)]}

        Map.has_key?(config.groups, name) ->
          group = Map.fetch!(config.groups, name)

          hosts =
            Enum.map(group.hosts, fn host_name ->
              Map.fetch!(config.hosts, host_name)
            end)

          {:ok, hosts}

        true ->
          {:error, "unknown host or group: #{name}"}
      end
    end
  end
end

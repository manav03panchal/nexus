defmodule Nexus.Types do
  @moduledoc """
  Core type definitions for Nexus.

  This module defines the typed structs used throughout Nexus for
  configuration, tasks, commands, and hosts.
  """

  defmodule Host do
    @moduledoc """
    Represents a remote host for SSH connections.

    ## Options

      * `:user` - SSH username (default: from config or current user)
      * `:port` - SSH port (default: 22)
      * `:identity` - Path to SSH private key file
      * `:password` - Password for authentication (use `{:env, "VAR"}` for env var)
      * `:proxy` - Jump host name for ProxyJump
      * `:become` - Enable privilege escalation (default: false)
      * `:become_user` - User to become (default: "root")
      * `:become_method` - Method for privilege escalation (:sudo, :su, :doas)

    ## Examples

        # Simple host
        host :web, "example.com"

        # With options
        host :web, "example.com",
          user: "deploy",
          identity: "~/.ssh/deploy_key",
          port: 2222

        # With jump host
        host :internal, "10.0.0.5",
          user: "app",
          proxy: :bastion

        # With privilege escalation
        host :server, "server.example.com",
          user: "deploy",
          become: true,
          become_user: "root"

    """

    alias Nexus.CLI.Password

    @type password_source :: String.t() | {:env, String.t()} | :prompt
    @type become_method :: :sudo | :su | :doas

    @type t :: %__MODULE__{
            name: atom(),
            hostname: String.t(),
            user: String.t() | nil,
            port: pos_integer(),
            identity: String.t() | nil,
            password: password_source() | nil,
            proxy: atom() | nil,
            become: boolean(),
            become_user: String.t(),
            become_method: become_method(),
            ssh_options: keyword()
          }

    @enforce_keys [:name, :hostname]
    defstruct [
      :name,
      :hostname,
      :user,
      :identity,
      :password,
      :proxy,
      port: 22,
      become: false,
      become_user: "root",
      become_method: :sudo,
      ssh_options: []
    ]

    @doc """
    Creates a new Host with the given name, hostname, and options.

    ## Examples

        iex> Host.new(:web, "example.com", user: "deploy")
        %Host{name: :web, hostname: "example.com", user: "deploy", port: 22}

    """
    @spec new(atom(), String.t(), keyword()) :: t()
    def new(name, hostname, opts \\ []) when is_atom(name) and is_binary(hostname) do
      identity = Keyword.get(opts, :identity)
      # Expand ~ in identity path
      identity = if identity, do: expand_path(identity), else: nil

      %__MODULE__{
        name: name,
        hostname: hostname,
        user: Keyword.get(opts, :user),
        port: Keyword.get(opts, :port, 22),
        identity: identity,
        password: Keyword.get(opts, :password),
        proxy: Keyword.get(opts, :proxy),
        become: Keyword.get(opts, :become, false),
        become_user: Keyword.get(opts, :become_user, "root"),
        become_method: Keyword.get(opts, :become_method, :sudo),
        ssh_options: Keyword.get(opts, :ssh_options, [])
      }
    end

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
    @spec parse(atom(), String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
    def parse(name, host_string, opts \\ []) when is_atom(name) and is_binary(host_string) do
      case parse_host_string(host_string) do
        {:ok, hostname, user, port} ->
          # Merge parsed values with explicit options (options take precedence)
          opts = Keyword.put_new(opts, :user, user)
          opts = Keyword.put_new(opts, :port, port)
          {:ok, new(name, hostname, opts)}

        {:error, reason} ->
          {:error, reason}
      end
    end

    @doc """
    Resolves the password from its source.

    Returns `nil` if no password is configured.
    """
    @spec resolve_password(t()) :: String.t() | nil
    def resolve_password(%__MODULE__{password: nil}), do: nil
    def resolve_password(%__MODULE__{password: password}) when is_binary(password), do: password
    def resolve_password(%__MODULE__{password: {:env, var}}), do: System.get_env(var)

    def resolve_password(%__MODULE__{password: :prompt} = host) do
      Password.prompt_for_host(host.hostname, host.user)
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

    defp expand_path("~/" <> rest), do: Path.expand("~") <> "/" <> rest
    defp expand_path(path), do: path
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

    @type condition :: term()

    @type t :: %__MODULE__{
            cmd: String.t(),
            sudo: boolean(),
            user: String.t() | nil,
            timeout: pos_integer(),
            retries: non_neg_integer(),
            retry_delay: pos_integer(),
            when: condition()
          }

    @enforce_keys [:cmd]
    defstruct [
      :cmd,
      :user,
      sudo: false,
      timeout: 60_000,
      retries: 0,
      retry_delay: 1_000,
      when: true
    ]

    @doc """
    Creates a new Command from a string or keyword options.

    ## Options

      * `:sudo` - Run with sudo (default: false)
      * `:user` - Run as specific user
      * `:timeout` - Command timeout in ms (default: 60_000)
      * `:retries` - Number of retries (default: 0)
      * `:retry_delay` - Delay between retries in ms (default: 1_000)
      * `:when` - Condition for execution (default: true)

    ## Examples

        iex> Nexus.Types.Command.new("echo hello")
        %Nexus.Types.Command{cmd: "echo hello", sudo: false, timeout: 60_000, retries: 0, retry_delay: 1_000, when: true}

        iex> Nexus.Types.Command.new("apt update", sudo: true, retries: 3)
        %Nexus.Types.Command{cmd: "apt update", sudo: true, timeout: 60_000, retries: 3, retry_delay: 1_000, when: true}

    """
    @spec new(String.t(), keyword()) :: t()
    def new(cmd, opts \\ []) when is_binary(cmd) do
      %__MODULE__{
        cmd: cmd,
        sudo: Keyword.get(opts, :sudo, false),
        user: Keyword.get(opts, :user),
        timeout: Keyword.get(opts, :timeout, 60_000),
        retries: Keyword.get(opts, :retries, 0),
        retry_delay: Keyword.get(opts, :retry_delay, 1_000),
        when: Keyword.get(opts, :when, true)
      }
    end
  end

  defmodule Task do
    @moduledoc """
    Represents a task definition with commands and dependencies.
    """

    alias Nexus.Types.Artifact

    @type strategy :: :parallel | :serial | :rolling
    @type condition :: term()

    @type t :: %__MODULE__{
            name: atom(),
            deps: [atom()],
            on: atom() | :local,
            commands: [Command.t()],
            timeout: pos_integer(),
            strategy: strategy(),
            batch_size: pos_integer(),
            canary_hosts: pos_integer(),
            canary_wait: pos_integer(),
            tags: [atom()],
            when: condition(),
            artifacts: [Artifact.t()]
          }

    @enforce_keys [:name]
    defstruct [
      :name,
      deps: [],
      on: :local,
      commands: [],
      timeout: 300_000,
      strategy: :parallel,
      batch_size: 1,
      canary_hosts: 1,
      canary_wait: 60,
      tags: [],
      when: true,
      artifacts: []
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
        strategy: Keyword.get(opts, :strategy, :parallel),
        batch_size: Keyword.get(opts, :batch_size, 1),
        canary_hosts: Keyword.get(opts, :canary_hosts, 1),
        canary_wait: Keyword.get(opts, :canary_wait, 60),
        tags: Keyword.get(opts, :tags, []) |> normalize_tags(),
        when: Keyword.get(opts, :when, true)
      }
    end

    defp normalize_tags(tags) when is_list(tags), do: Enum.map(tags, &to_atom/1)
    defp normalize_tags(tag), do: [to_atom(tag)]

    defp to_atom(tag) when is_atom(tag), do: tag
    defp to_atom(tag) when is_binary(tag), do: String.to_atom(tag)

    @doc """
    Checks if a task has any of the given tags.
    """
    @spec has_tag?(t(), atom() | [atom()]) :: boolean()
    def has_tag?(%__MODULE__{tags: task_tags}, tags) when is_list(tags) do
      Enum.any?(tags, &(&1 in task_tags))
    end

    def has_tag?(%__MODULE__{} = task, tag) when is_atom(tag) do
      has_tag?(task, [tag])
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

    alias Nexus.Types.{Handler, Notification}

    @type t :: %__MODULE__{
            default_user: String.t() | nil,
            default_port: pos_integer(),
            connect_timeout: pos_integer(),
            command_timeout: pos_integer(),
            max_connections: pos_integer(),
            continue_on_error: boolean(),
            hosts: %{atom() => Host.t()},
            groups: %{atom() => HostGroup.t()},
            tasks: %{atom() => Task.t()},
            handlers: %{atom() => Handler.t()},
            notifications: [Notification.t()]
          }

    defstruct default_user: nil,
              default_port: 22,
              connect_timeout: 10_000,
              command_timeout: 60_000,
              max_connections: 5,
              continue_on_error: false,
              hosts: %{},
              groups: %{},
              tasks: %{},
              handlers: %{},
              notifications: []

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
    Adds a handler to the configuration.
    """
    @spec add_handler(t(), Handler.t()) :: t()
    def add_handler(%__MODULE__{} = config, %Handler{} = handler) do
      %{config | handlers: Map.put(config.handlers, handler.name, handler)}
    end

    @doc """
    Adds a notification configuration.
    """
    @spec add_notification(t(), Notification.t()) :: t()
    def add_notification(%__MODULE__{} = config, %Notification{} = notification) do
      %{config | notifications: config.notifications ++ [notification]}
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

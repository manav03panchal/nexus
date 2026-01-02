defmodule Nexus.DSL.Parser do
  @moduledoc """
  Parser for Nexus DSL configuration files.

  Parses `nexus.exs` files which use an Elixir-based DSL to define
  hosts, groups, tasks, and configuration options.

  ## Example DSL

      config :nexus,
        default_user: "deploy",
        default_port: 22

      host :web1, "web1.example.com"
      host :web2, "deploy@web2.example.com:2222"

      group :web, [:web1, :web2]

      task :deploy, deps: [:build], on: :web do
        run "git pull"
        run "mix deps.get"
        run "mix compile"
      end

  """

  alias Nexus.Types.{Command, Config, Download, Host, HostGroup, Task, Upload}

  @type parse_error :: {:error, String.t()}
  @type parse_result :: {:ok, Config.t()} | parse_error()

  @doc """
  Parses a nexus.exs file at the given path.

  Returns `{:ok, config}` on success or `{:error, reason}` on failure.
  """
  @spec parse_file(Path.t()) :: parse_result()
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} ->
        parse_string(content, path)

      {:error, reason} ->
        {:error, "failed to read file #{path}: #{:file.format_error(reason)}"}
    end
  end

  @doc """
  Parses a DSL string directly.

  The optional `file` parameter is used for error messages.
  """
  @spec parse_string(String.t(), String.t()) :: parse_result()
  def parse_string(content, file \\ "nofile") do
    do_parse_string(content, file)
  rescue
    e in [CompileError, SyntaxError, TokenMissingError] ->
      {:error, "syntax error: #{Exception.message(e)}"}

    e in ArgumentError ->
      {:error, "argument error: #{Exception.message(e)}"}

    e ->
      {:error, "unexpected error: #{Exception.message(e)}"}
  end

  defp do_parse_string(content, file) do
    # Create a new parser state
    state = %{
      config: Config.new(),
      current_task: nil,
      file: file
    }

    # Set up the DSL bindings
    bindings = [
      {:__nexus_state__, state},
      {:config, &handle_config/2},
      {:host, &handle_host/2},
      {:group, &handle_group/2},
      {:task, &handle_task/2},
      {:run, &handle_run/2},
      {:env, &handle_env/1}
    ]

    # Evaluate the DSL using a custom environment
    {result, _bindings} = Code.eval_string(wrap_dsl(content), bindings, file: file)

    case result do
      %Config{} = config ->
        {:ok, config}

      {:error, _} = error ->
        error

      _ ->
        {:error, "DSL evaluation did not return a valid configuration"}
    end
  end

  # Wraps the DSL content in a module that provides the DSL functions
  defp wrap_dsl(content) do
    # Ensure we have a valid expression even for empty content
    body = if String.trim(content) == "", do: ":ok", else: content

    """
    import Nexus.DSL.Parser.DSL
    Nexus.DSL.Parser.DSL.run_dsl(fn ->
    #{body}
    end)
    """
  end

  # DSL handler functions (these are passed as bindings but the actual
  # implementation is in the DSL submodule)

  defp handle_config(app, opts) when is_atom(app) and is_list(opts), do: :ok
  defp handle_host(name, host_string), do: {name, host_string}
  defp handle_group(name, hosts), do: {name, hosts}
  defp handle_task(name, opts), do: {name, opts}
  defp handle_run(cmd, opts), do: {cmd, opts}
  defp handle_env(var), do: System.get_env(to_string(var)) || ""
end

defmodule Nexus.DSL.Parser.DSL do
  @moduledoc false
  # Internal module that provides the DSL macros and functions

  alias Nexus.Types.{Command, Config, Download, Host, HostGroup, Task, Upload}

  @doc false
  def run_dsl(fun) do
    # Initialize process dictionary for state
    Process.put(:nexus_config, Config.new())
    Process.put(:nexus_current_task, nil)

    # Execute the DSL
    fun.()

    # Return the final config
    Process.get(:nexus_config)
  end

  @doc """
  Configures Nexus options.

  ## Example

      config :nexus,
        default_user: "deploy",
        connect_timeout: 30_000

  """
  defmacro config(app, opts) do
    quote do
      unquote(__MODULE__).do_config(unquote(app), unquote(opts))
    end
  end

  def do_config(:nexus, opts) when is_list(opts) do
    config = Process.get(:nexus_config)

    updated =
      Enum.reduce(opts, config, fn
        {:default_user, value}, acc -> %{acc | default_user: value}
        {:default_port, value}, acc -> %{acc | default_port: value}
        {:connect_timeout, value}, acc -> %{acc | connect_timeout: value}
        {:command_timeout, value}, acc -> %{acc | command_timeout: value}
        {:max_connections, value}, acc -> %{acc | max_connections: value}
        {:continue_on_error, value}, acc -> %{acc | continue_on_error: value}
        {key, _value}, _acc -> raise ArgumentError, "unknown config option: #{key}"
      end)

    Process.put(:nexus_config, updated)
    :ok
  end

  @doc """
  Defines a host.

  ## Examples

      host :web1, "example.com"
      host :web2, "deploy@example.com"
      host :web3, "deploy@example.com:2222"

  """
  defmacro host(name, host_string) do
    quote do
      unquote(__MODULE__).do_host(unquote(name), unquote(host_string))
    end
  end

  def do_host(name, host_string) when is_atom(name) and is_binary(host_string) do
    config = Process.get(:nexus_config)

    case Host.parse(name, host_string) do
      {:ok, host} ->
        # Apply default user if not specified in host string
        host =
          if is_nil(host.user) and not is_nil(config.default_user) do
            %{host | user: config.default_user}
          else
            host
          end

        # Apply default port if using default
        host =
          if host.port == 22 and config.default_port != 22 do
            %{host | port: config.default_port}
          else
            host
          end

        Process.put(:nexus_config, Config.add_host(config, host))
        :ok

      {:error, reason} ->
        raise ArgumentError, reason
    end
  end

  @doc """
  Defines a host group.

  ## Example

      group :web, [:web1, :web2, :web3]

  """
  defmacro group(name, hosts) do
    quote do
      unquote(__MODULE__).do_group(unquote(name), unquote(hosts))
    end
  end

  def do_group(name, hosts) when is_atom(name) and is_list(hosts) do
    config = Process.get(:nexus_config)
    group = %HostGroup{name: name, hosts: hosts}
    Process.put(:nexus_config, Config.add_group(config, group))
    :ok
  end

  @doc """
  Defines a task with optional dependencies and target hosts.

  ## Examples

      task :build do
        run "mix compile"
      end

      task :deploy, deps: [:build], on: :web do
        run "git pull"
        run "mix deps.get"
      end

      task :restart, on: :web, strategy: :serial do
        run "sudo systemctl restart app"
      end

  """
  defmacro task(name, opts \\ [], do: block) do
    quote do
      unquote(__MODULE__).do_task(unquote(name), unquote(opts), fn ->
        unquote(block)
      end)
    end
  end

  def do_task(name, opts, block_fn) when is_atom(name) and is_list(opts) do
    config = Process.get(:nexus_config)

    task = %Task{
      name: name,
      deps: Keyword.get(opts, :deps, []),
      on: Keyword.get(opts, :on, :local),
      timeout: Keyword.get(opts, :timeout, 300_000),
      strategy: Keyword.get(opts, :strategy, :parallel),
      commands: []
    }

    # Set current task for run commands
    Process.put(:nexus_current_task, task)

    # Execute the block to collect commands
    block_fn.()

    # Get the updated task with commands
    task = Process.get(:nexus_current_task)
    Process.put(:nexus_current_task, nil)

    # Add task to config
    Process.put(:nexus_config, Config.add_task(config, task))
    :ok
  end

  @doc """
  Adds a command to the current task.

  ## Examples

      run "echo hello"
      run "apt update", sudo: true
      run "deploy.sh", timeout: 120_000, retries: 3

  """
  defmacro run(cmd, opts \\ []) do
    quote do
      unquote(__MODULE__).do_run(unquote(cmd), unquote(opts))
    end
  end

  def do_run(cmd, opts) when is_binary(cmd) and is_list(opts) do
    task = Process.get(:nexus_current_task)

    if is_nil(task) do
      raise ArgumentError, "run must be called inside a task block"
    end

    command = Command.new(cmd, opts)
    updated_task = Task.add_command(task, command)
    Process.put(:nexus_current_task, updated_task)
    :ok
  end

  @doc """
  Uploads a local file to remote hosts.

  ## Options

    * `:sudo` - Upload to a location requiring root access
    * `:mode` - File permissions to set (e.g., 0o644)
    * `:notify` - Handler to trigger after upload

  ## Examples

      task :deploy, on: :web do
        upload "dist/app.tar.gz", "/opt/app/release.tar.gz"
        upload "config.txt", "/etc/app/config.txt", sudo: true, mode: 0o644
      end

  """
  defmacro upload(local_path, remote_path, opts \\ []) do
    quote do
      unquote(__MODULE__).do_upload(unquote(local_path), unquote(remote_path), unquote(opts))
    end
  end

  def do_upload(local_path, remote_path, opts)
      when is_binary(local_path) and is_binary(remote_path) and is_list(opts) do
    task = Process.get(:nexus_current_task)

    if is_nil(task) do
      raise ArgumentError, "upload must be called inside a task block"
    end

    upload_cmd = Upload.new(local_path, remote_path, opts)
    updated_task = add_command_to_task(task, upload_cmd)
    Process.put(:nexus_current_task, updated_task)
    :ok
  end

  @doc """
  Downloads a file from remote hosts to a local path.

  ## Options

    * `:sudo` - Download from a location requiring root access

  ## Examples

      task :collect_logs, on: :web do
        download "/var/log/app.log", "logs/app.log"
      end

  """
  defmacro download(remote_path, local_path, opts \\ []) do
    quote do
      unquote(__MODULE__).do_download(unquote(remote_path), unquote(local_path), unquote(opts))
    end
  end

  def do_download(remote_path, local_path, opts)
      when is_binary(remote_path) and is_binary(local_path) and is_list(opts) do
    task = Process.get(:nexus_current_task)

    if is_nil(task) do
      raise ArgumentError, "download must be called inside a task block"
    end

    download_cmd = Download.new(remote_path, local_path, opts)
    updated_task = add_command_to_task(task, download_cmd)
    Process.put(:nexus_current_task, updated_task)
    :ok
  end

  # Helper to add any command type to a task
  defp add_command_to_task(%Task{} = task, command) do
    %{task | commands: task.commands ++ [command]}
  end

  @doc """
  Retrieves an environment variable value.

  ## Example

      config :nexus,
        default_user: env("DEPLOY_USER")

  """
  defmacro env(var) do
    quote do
      unquote(__MODULE__).do_env(unquote(var))
    end
  end

  def do_env(var) when is_binary(var) do
    System.get_env(var) || ""
  end

  def do_env(var) when is_atom(var) do
    System.get_env(to_string(var)) || ""
  end

  @doc """
  Retrieves a secret value from the encrypted vault.

  Secrets must be set using `nexus secret set <name> <value>` before use.

  ## Examples

      task :deploy do
        run "docker login -p \#{secret("DOCKER_PASSWORD")}"
      end

      task :db_migrate do
        run "DATABASE_URL=\#{secret("DATABASE_URL")} mix ecto.migrate"
      end

  """
  defmacro secret(name) do
    quote do
      unquote(__MODULE__).do_secret(unquote(name))
    end
  end

  def do_secret(name) when is_binary(name) do
    alias Nexus.Secrets.Vault

    case Vault.get(name) do
      {:ok, value} ->
        value

      {:error, :not_found} ->
        raise ArgumentError,
              "secret '#{name}' not found. Use 'nexus secret set #{name}' to add it."

      {:error, :no_key_available} ->
        raise ArgumentError,
              "no master key available. Run 'nexus secret init' first."

      {:error, reason} ->
        raise ArgumentError, "failed to retrieve secret '#{name}': #{inspect(reason)}"
    end
  end

  def do_secret(name) when is_atom(name) do
    do_secret(to_string(name))
  end
end

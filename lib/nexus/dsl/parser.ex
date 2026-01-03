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

  alias Nexus.Types.{Command, Config, Download, Host, HostGroup, Task, Template, Upload, WaitFor}

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

  alias Nexus.DSL.Importer

  alias Nexus.Types.{
    Artifact,
    Command,
    Config,
    Download,
    Handler,
    Host,
    HostGroup,
    Notification,
    Task,
    Template,
    Upload,
    WaitFor
  }

  @doc false
  def run_dsl(fun) do
    # Initialize process dictionary for state
    Process.put(:nexus_config, Config.new())
    Process.put(:nexus_current_task, nil)
    Process.put(:nexus_current_handler, nil)
    Process.put(:nexus_import_chain, MapSet.new())
    Process.put(:nexus_base_path, File.cwd!())

    # Execute the DSL
    fun.()

    # Return the final config
    Process.get(:nexus_config)
  end

  @doc false
  def run_dsl_with_context(fun, base_path, import_chain) do
    # Store context for nested imports
    Process.put(:nexus_base_path, base_path)
    Process.put(:nexus_import_chain, import_chain)

    # Execute the DSL
    fun.()
  end

  @doc """
  Imports configuration from another file.

  The imported file can contain any DSL constructs (config, hosts, groups).
  Relative paths are resolved from the importing file's directory.

  ## Examples

      import_config "config/hosts.exs"
      import_config "config/production.exs"

  """
  defmacro import_config(path) do
    quote do
      unquote(__MODULE__).do_import(unquote(path), :config)
    end
  end

  @doc """
  Imports tasks from files matching a glob pattern.

  Supports glob patterns for importing multiple files at once.
  Files are processed in alphabetical order for deterministic results.

  ## Examples

      import_tasks "tasks/build.exs"
      import_tasks "tasks/*.exs"
      import_tasks "tasks/**/*.exs"

  """
  defmacro import_tasks(pattern) do
    quote do
      unquote(__MODULE__).do_import(unquote(pattern), :tasks)
    end
  end

  @doc """
  Imports handlers from files matching a glob pattern.

  ## Examples

      import_handlers "handlers/*.exs"

  """
  defmacro import_handlers(pattern) do
    quote do
      unquote(__MODULE__).do_import(unquote(pattern), :handlers)
    end
  end

  def do_import(pattern, _type) when is_binary(pattern) do
    base_path = Process.get(:nexus_base_path, File.cwd!())
    import_chain = Process.get(:nexus_import_chain, MapSet.new())

    if Importer.glob_pattern?(pattern) do
      import_glob_pattern(pattern, base_path, import_chain)
    else
      import_single_pattern(pattern, base_path, import_chain)
    end

    :ok
  end

  defp import_glob_pattern(pattern, base_path, import_chain) do
    case Importer.resolve_glob(pattern, base_path: base_path) do
      {:ok, files} ->
        Enum.each(files, fn {file_path, content} ->
          import_single_file(file_path, content, import_chain)
        end)

      {:error, reason} ->
        raise ArgumentError, "import failed: #{reason}"
    end
  end

  defp import_single_pattern(pattern, base_path, import_chain) do
    case Importer.resolve_file(pattern, base_path: base_path) do
      {:ok, file_path, content} ->
        import_single_file(file_path, content, import_chain)

      {:error, reason} ->
        raise ArgumentError, "import failed: #{reason}"
    end
  end

  defp import_single_file(file_path, content, import_chain) do
    # Check for circular imports
    case Importer.check_circular_import(file_path, import_chain) do
      {:ok, updated_chain} ->
        # Get the directory of the imported file for nested imports
        new_base_path = Importer.base_dir(file_path)

        # Evaluate the imported file with updated context
        run_dsl_with_context(
          fn ->
            Code.eval_string(wrap_import(content), [], file: file_path)
          end,
          new_base_path,
          updated_chain
        )

      {:error, reason} ->
        raise ArgumentError, reason
    end
  end

  defp wrap_import(content) do
    """
    import Nexus.DSL.Parser.DSL
    #{content}
    """
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
  defmacro host(name, host_string, opts \\ []) do
    quote do
      unquote(__MODULE__).do_host(unquote(name), unquote(host_string), unquote(opts))
    end
  end

  def do_host(name, host_string, opts \\ []) when is_atom(name) and is_binary(host_string) do
    config = Process.get(:nexus_config)

    case Host.parse(name, host_string, opts) do
      {:ok, host} ->
        # Apply default user if not specified
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

  Note: When the first argument is a string, this is treated as a Group resource
  (for user group management). When the first argument is an atom, it's a host group.
  """
  defmacro group(name, hosts) when is_atom(name) do
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
      batch_size: Keyword.get(opts, :batch_size, 1),
      canary_hosts: Keyword.get(opts, :canary_hosts, 1),
      canary_wait: Keyword.get(opts, :canary_wait, 60),
      tags: Keyword.get(opts, :tags, []),
      when: Keyword.get(opts, :when, true),
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
  Defines a handler that can be triggered by notify options.

  Handlers are named blocks of commands that execute when triggered
  by upload, download, or template commands with `:notify`.

  ## Examples

      handler :restart_nginx do
        run "systemctl restart nginx", sudo: true
      end

      handler :reload_app do
        run "systemctl reload app"
        run "sleep 2"
      end

  """
  defmacro handler(name, do: block) do
    quote do
      unquote(__MODULE__).do_handler(unquote(name), fn ->
        unquote(block)
      end)
    end
  end

  def do_handler(name, block_fn) when is_atom(name) do
    config = Process.get(:nexus_config)

    handler = Handler.new(name)

    # Set current handler for run commands
    Process.put(:nexus_current_handler, handler)

    # Execute the block to collect commands
    block_fn.()

    # Get the updated handler with commands
    handler = Process.get(:nexus_current_handler)
    Process.put(:nexus_current_handler, nil)

    # Add handler to config
    Process.put(:nexus_config, Config.add_handler(config, handler))
    :ok
  end

  @doc """
  Adds a command to the current task.

  > #### Deprecation Notice {: .warning}
  >
  > The `run` macro is deprecated and will be removed in v1.0.
  > Use the `command` resource instead for better idempotency:
  >
  >     # Old way (deprecated)
  >     run "mix deps.get"
  >
  >     # New way (recommended)
  >     command "mix deps.get", creates: "deps/"

  ## Examples

      run "echo hello"
      run "apt update", sudo: true
      run "deploy.sh", timeout: 120_000, retries: 3

  """
  defmacro run(cmd, opts \\ []) do
    # Transform the when: option to preserve comparison operators as data
    transformed_opts = transform_when_option(opts)

    quote do
      # Emit deprecation warning only when used in task blocks (not handlers)
      # Handlers still use run/2 as the primary way to execute commands
      if Process.get(:nexus_current_task) != nil and
           not Process.get(:nexus_run_deprecation_warned, false) do
        IO.warn(
          "run/2 is deprecated in task blocks, use command/2 resource instead for idempotent execution",
          []
        )

        Process.put(:nexus_run_deprecation_warned, true)
      end

      unquote(__MODULE__).do_run(unquote(cmd), unquote(transformed_opts))
    end
  end

  # Transform when: option to preserve comparison as data structure
  defp transform_when_option(opts) do
    case Keyword.get(opts, :when) do
      nil ->
        opts

      condition ->
        transformed = transform_condition(condition)
        Keyword.put(opts, :when, transformed)
    end
  end

  defp transform_condition({:==, _, [left, right]}) do
    quote do: {:==, unquote(transform_condition(left)), unquote(transform_condition(right))}
  end

  defp transform_condition({:!=, _, [left, right]}) do
    quote do: {:!=, unquote(transform_condition(left)), unquote(transform_condition(right))}
  end

  defp transform_condition({:<, _, [left, right]}) do
    quote do: {:<, unquote(transform_condition(left)), unquote(transform_condition(right))}
  end

  defp transform_condition({:>, _, [left, right]}) do
    quote do: {:>, unquote(transform_condition(left)), unquote(transform_condition(right))}
  end

  defp transform_condition({:<=, _, [left, right]}) do
    quote do: {:<=, unquote(transform_condition(left)), unquote(transform_condition(right))}
  end

  defp transform_condition({:>=, _, [left, right]}) do
    quote do: {:>=, unquote(transform_condition(left)), unquote(transform_condition(right))}
  end

  defp transform_condition({:and, _, [left, right]}) do
    quote do: {:and, unquote(transform_condition(left)), unquote(transform_condition(right))}
  end

  defp transform_condition({:or, _, [left, right]}) do
    quote do: {:or, unquote(transform_condition(left)), unquote(transform_condition(right))}
  end

  defp transform_condition({:not, _, [expr]}) do
    quote do: {:not, unquote(transform_condition(expr))}
  end

  defp transform_condition({:in, _, [left, right]}) do
    quote do: {:in, unquote(transform_condition(left)), unquote(transform_condition(right))}
  end

  # facts(:name) call - preserve as {:nexus_fact, name}
  defp transform_condition({:facts, _, [name]}) do
    quote do: {:nexus_fact, unquote(name)}
  end

  # Literal values pass through
  defp transform_condition(other) do
    other
  end

  def do_run(cmd, opts) when is_binary(cmd) and is_list(opts) do
    task = Process.get(:nexus_current_task)
    handler = Process.get(:nexus_current_handler)

    command = Command.new(cmd, opts)

    cond do
      not is_nil(task) ->
        updated_task = Task.add_command(task, command)
        Process.put(:nexus_current_task, updated_task)
        :ok

      not is_nil(handler) ->
        updated_handler = Handler.add_command(handler, command)
        Process.put(:nexus_current_handler, updated_handler)
        :ok

      true ->
        raise ArgumentError, "run must be called inside a task or handler block"
    end
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

  @doc """
  Renders an EEx template and uploads it to remote hosts.

  Templates are rendered locally with variable substitution, then uploaded.
  Variables are available in templates as `@var_name`.

  ## Options

    * `:vars` - Map of variables to bind in the template
    * `:sudo` - Upload to a location requiring root access
    * `:mode` - File permissions to set (e.g., 0o644)
    * `:notify` - Handler to trigger after template upload

  ## Examples

      task :configure, on: :web do
        template "templates/nginx.conf.eex", "/etc/nginx/nginx.conf",
          vars: %{port: 8080, workers: 4},
          sudo: true,
          mode: 0o644
      end

  """
  defmacro template(source, destination, opts \\ []) do
    quote do
      unquote(__MODULE__).do_template(unquote(source), unquote(destination), unquote(opts))
    end
  end

  def do_template(source, destination, opts)
      when is_binary(source) and is_binary(destination) and is_list(opts) do
    task = Process.get(:nexus_current_task)

    if is_nil(task) do
      raise ArgumentError, "template must be called inside a task block"
    end

    template_cmd = Template.new(source, destination, opts)
    updated_task = add_command_to_task(task, template_cmd)
    Process.put(:nexus_current_task, updated_task)
    :ok
  end

  @doc """
  Waits for a health check to pass before continuing.

  Used in rolling deployments to verify services are healthy
  before proceeding to the next batch of hosts.

  ## Types

    * `:http` - HTTP GET request, checks for 2xx status
    * `:tcp` - TCP connection check
    * `:command` - Shell command, checks for exit code 0

  ## Options

    * `:timeout` - Total time to wait in milliseconds (default: 60_000)
    * `:interval` - Time between checks in milliseconds (default: 5_000)
    * `:expected_status` - Expected HTTP status code (for :http)
    * `:expected_body` - Expected body pattern (for :http)

  ## Examples

      task :deploy, on: :web, strategy: :rolling do
        run "systemctl restart app", sudo: true
        wait_for :http, "http://localhost:4000/health",
          timeout: 60_000,
          interval: 5_000
      end

      task :db_check, on: :db do
        wait_for :tcp, "localhost:5432", timeout: 30_000
      end

  """
  defmacro wait_for(type, target, opts \\ []) do
    quote do
      unquote(__MODULE__).do_wait_for(unquote(type), unquote(target), unquote(opts))
    end
  end

  def do_wait_for(type, target, opts)
      when type in [:http, :tcp, :command] and is_binary(target) and is_list(opts) do
    task = Process.get(:nexus_current_task)

    if is_nil(task) do
      raise ArgumentError, "wait_for must be called inside a task block"
    end

    wait_for_cmd = WaitFor.new(type, target, opts)
    updated_task = add_command_to_task(task, wait_for_cmd)
    Process.put(:nexus_current_task, updated_task)
    :ok
  end

  # Helper to add any command type to a task
  defp add_command_to_task(%Task{} = task, command) do
    %{task | commands: task.commands ++ [command]}
  end

  @doc """
  Declares an artifact produced by this task.

  Artifacts are files that are produced by one task and consumed by
  dependent tasks. They are automatically transferred between hosts.

  ## Options

    * `:as` - Alternative name for referencing the artifact

  ## Examples

      task :build, on: :builder do
        run "make"
        artifact "build/output.tar.gz"
      end

      task :deploy, on: :web, deps: [:build] do
        # artifact automatically available at same path
        run "tar -xzf build/output.tar.gz"
      end

      # With alias
      task :compile do
        run "npm run build"
        artifact "dist/bundle.js", as: "app.js"
      end

  """
  defmacro artifact(path, opts \\ []) do
    quote do
      unquote(__MODULE__).do_artifact(unquote(path), unquote(opts))
    end
  end

  def do_artifact(path, opts) when is_binary(path) and is_list(opts) do
    task = Process.get(:nexus_current_task)

    if is_nil(task) do
      raise ArgumentError, "artifact must be called inside a task block"
    end

    artifact = Artifact.new(path, opts)

    # Store artifact declaration in task
    artifacts = Map.get(task, :artifacts, [])
    updated_task = Map.put(task, :artifacts, artifacts ++ [artifact])
    Process.put(:nexus_current_task, updated_task)
    :ok
  end

  @doc """
  References an artifact for use in upload or other commands.

  Returns the local path where the artifact will be available.

  ## Examples

      task :deploy, deps: [:build] do
        upload get_artifact("app.js"), "/var/www/app.js"
      end

  """
  defmacro get_artifact(name) do
    quote do
      unquote(__MODULE__).do_artifact_ref(unquote(name))
    end
  end

  def do_artifact_ref(name) when is_binary(name) do
    # Return a placeholder that will be resolved at runtime
    {:nexus_artifact, name}
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

  # ===========================================================================
  # Context Helper Functions
  # ===========================================================================

  @doc """
  Returns the current hostname.

  During task execution on remote hosts, returns the remote hostname.
  During local execution or DSL parsing, returns the local hostname.

  ## Examples

      task :deploy do
        run "echo 'Deploying to \#{hostname()}'"
      end

      task :backup do
        download "/var/log/app.log", to: "logs/\#{hostname()}.log"
      end

  """
  defmacro hostname do
    quote do
      unquote(__MODULE__).do_hostname()
    end
  end

  def do_hostname do
    # During DSL parsing, return local hostname
    # At runtime on remote hosts, this gets the remote hostname
    case Process.get(:nexus_current_host) do
      nil ->
        {:ok, hostname} = :inet.gethostname()
        to_string(hostname)

      %{hostname: hostname} ->
        hostname

      host when is_binary(host) ->
        host
    end
  end

  @doc """
  Returns the current timestamp in ISO 8601 format.

  Useful for creating timestamped backups, logs, or artifacts.

  ## Examples

      task :backup do
        run "pg_dump mydb > backup_\#{timestamp()}.sql"
      end

      task :deploy do
        run "echo 'Deployed at \#{timestamp()}' >> /var/log/deploys.log"
      end

  """
  defmacro timestamp do
    quote do
      unquote(__MODULE__).do_timestamp()
    end
  end

  def do_timestamp do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  @doc """
  Returns the current git commit SHA (short form).

  Returns the 7-character short SHA of the current HEAD commit.
  Returns "unknown" if not in a git repository.

  ## Examples

      task :deploy do
        run "echo 'Deploying version \#{git_sha()}'"
      end

      task :tag do
        run "docker tag myapp myapp:\#{git_sha()}"
      end

  """
  defmacro git_sha do
    quote do
      unquote(__MODULE__).do_git_sha()
    end
  end

  def do_git_sha do
    case System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> "unknown"
    end
  end

  @doc """
  Returns the current git branch name.

  Returns "unknown" if not in a git repository or in detached HEAD state.

  ## Examples

      task :deploy, when: git_branch() == "main" do
        run "deploy-to-production.sh"
      end

      task :notify do
        run "echo 'Building branch: \#{git_branch()}'"
      end

  """
  defmacro git_branch do
    quote do
      unquote(__MODULE__).do_git_branch()
    end
  end

  def do_git_branch do
    case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"], stderr_to_stdout: true) do
      {branch, 0} -> String.trim(branch)
      _ -> "unknown"
    end
  end

  @doc """
  Returns the current git tag if HEAD is tagged.

  Returns nil if HEAD is not tagged.

  ## Examples

      task :release, when: git_tag() != nil do
        run "publish-release.sh \#{git_tag()}"
      end

  """
  defmacro git_tag do
    quote do
      unquote(__MODULE__).do_git_tag()
    end
  end

  def do_git_tag do
    case System.cmd("git", ["describe", "--tags", "--exact-match", "HEAD"],
           stderr_to_stdout: true
         ) do
      {tag, 0} -> String.trim(tag)
      _ -> nil
    end
  end

  # ===========================================================================
  # Sharding Functions (for distributed parallel execution)
  # ===========================================================================

  @doc """
  Returns the shard ID for the current task execution.

  When a task runs with `parallel: :sharded`, each instance gets a unique
  shard ID (0-indexed). Use this to divide work across nodes.

  Returns 0 during DSL parsing or non-sharded execution.

  ## Examples

      task :process, on: {:all}, parallel: :sharded do
        run "process.sh --shard \#{shard_id()} --total \#{shard_count()}"
      end

  """
  defmacro shard_id do
    quote do
      unquote(__MODULE__).do_shard_id()
    end
  end

  def do_shard_id do
    case Process.get(:nexus_shard_id) do
      nil ->
        case System.get_env("NEXUS_SHARD_ID") do
          nil -> 0
          val -> String.to_integer(val)
        end

      id ->
        id
    end
  end

  @doc """
  Returns the total number of shards for the current task.

  Returns 1 during DSL parsing or non-sharded execution.

  ## Examples

      task :encode, on: {:tag, :encoder}, parallel: :sharded do
        run "ffmpeg -i input.mp4 -ss \#{shard_start()} -t \#{shard_duration()} chunk_\#{shard_id()}.mp4"
      end

  """
  defmacro shard_count do
    quote do
      unquote(__MODULE__).do_shard_count()
    end
  end

  def do_shard_count do
    case Process.get(:nexus_shard_count) do
      nil ->
        case System.get_env("NEXUS_SHARD_COUNT") do
          nil -> 1
          val -> String.to_integer(val)
        end

      count ->
        count
    end
  end

  @doc """
  Returns the subset of items for the current shard.

  Divides a list evenly across all shards and returns the items
  for this shard. Useful for batch processing.

  ## Examples

      task :process_files, on: {:all}, parallel: :sharded do
        files = ["a.txt", "b.txt", "c.txt", "d.txt", "e.txt", "f.txt"]
        my_files = shard_items(files)
        # Shard 0 gets ["a.txt", "b.txt"], shard 1 gets ["c.txt", "d.txt"], etc.
        Enum.each(my_files, fn f -> run "process \#{f}" end)
      end

  """
  defmacro shard_items(list) do
    quote do
      unquote(__MODULE__).do_shard_items(unquote(list))
    end
  end

  def do_shard_items(list) when is_list(list) do
    shard = do_shard_id()
    count = do_shard_count()

    list
    |> Enum.with_index()
    |> Enum.filter(fn {_item, idx} -> rem(idx, count) == shard end)
    |> Enum.map(fn {item, _idx} -> item end)
  end

  @doc """
  Retrieves a fact about the current host.

  Facts are gathered lazily on first access and cached for the pipeline run.
  During DSL parsing (before execution), facts return placeholder values.
  Actual values are resolved at runtime during task execution.

  ## Available Facts

    * `:os` - Operating system (`:linux`, `:darwin`, `:windows`)
    * `:os_family` - OS family (`:debian`, `:rhel`, `:arch`, `:darwin`)
    * `:os_version` - OS version string (e.g., "22.04")
    * `:hostname` - Short hostname
    * `:fqdn` - Fully qualified domain name
    * `:cpu_count` - Number of CPU cores
    * `:memory_mb` - Total memory in MB
    * `:arch` - CPU architecture (`:x86_64`, `:aarch64`)
    * `:kernel_version` - Kernel version string
    * `:user` - Current SSH user

  ## Examples

      task :install, on: :web do
        run "apt install nginx", when: facts(:os_family) == :debian
        run "yum install nginx", when: facts(:os_family) == :rhel
      end

      task :report do
        run "echo 'Host has \#{facts(:cpu_count)} CPUs'"
      end

  """
  defmacro facts(name) do
    quote do
      unquote(__MODULE__).do_facts(unquote(name))
    end
  end

  def do_facts(name) when is_atom(name) do
    # During DSL parsing, we return a placeholder that will be resolved at runtime.
    # The actual fact value is determined during task execution via the Facts module.
    {:nexus_fact, name}
  end

  def do_facts(name) when is_binary(name) do
    do_facts(String.to_atom(name))
  end

  @doc """
  Discovers hosts from Tailscale network and adds them as a group.

  This macro queries the local Tailscale daemon for connected peers
  and filters them by ACL tags.

  ## Options

    * `:tag` - (required) The Tailscale ACL tag to filter by (without "tag:" prefix)
    * `:as` - (required) The group name to assign discovered hosts to
    * `:user` - (optional) SSH user for all discovered hosts
    * `:online_only` - (optional) Only include online peers (default: true)

  ## Requirements

    * Tailscale must be installed and running
    * The `tailscale` CLI must be in PATH
    * Hosts must have ACL tags configured in Tailscale admin console

  ## Examples

      # Discover all hosts with tag:webserver and add them to :web group
      tailscale_hosts tag: "webserver", as: :web

      # Discover hosts with tag:database, specify SSH user
      tailscale_hosts tag: "database", as: :db, user: "admin"

      # Include offline hosts too
      tailscale_hosts tag: "all", as: :fleet, online_only: false

  """
  defmacro tailscale_hosts(opts) do
    quote do
      unquote(__MODULE__).do_tailscale_hosts(unquote(opts))
    end
  end

  def do_tailscale_hosts(opts) when is_list(opts) do
    alias Nexus.Discovery.Tailscale

    config = Process.get(:nexus_config)

    case Tailscale.discover(config, opts) do
      {:ok, updated_config} ->
        Process.put(:nexus_config, updated_config)
        :ok

      {:error, reason} ->
        raise ArgumentError, "tailscale_hosts failed: #{reason}"
    end
  end

  @doc """
  Configures a notification webhook for pipeline events.

  Notifications are sent after pipeline completion to inform external
  services about deployment status.

  ## Options

    * `:template` - Message format (`:slack`, `:discord`, `:teams`, `:generic`)
    * `:on` - When to send (`:success`, `:failure`, `:always`) - default: `:always`
    * `:headers` - Additional HTTP headers as a map

  ## Examples

      # Slack notification on all events
      notify "https://hooks.slack.com/services/...",
        template: :slack

      # Discord notification only on failures
      notify "https://discord.com/api/webhooks/...",
        template: :discord,
        on: :failure

      # Teams notification with custom header
      notify "https://outlook.office.com/webhook/...",
        template: :teams,
        headers: %{"X-Custom-Header" => "value"}

      # Generic JSON webhook
      notify "https://api.example.com/deployments",
        on: [:success, :failure]

  """
  defmacro notify(url, opts \\ []) do
    quote do
      unquote(__MODULE__).do_notify(unquote(url), unquote(opts))
    end
  end

  def do_notify(url, opts) when is_binary(url) and is_list(opts) do
    config = Process.get(:nexus_config)
    notification = Notification.new(url, opts)
    Process.put(:nexus_config, Config.add_notification(config, notification))
    :ok
  end

  # ============================================================================
  # Declarative Resource DSL (v0.3)
  # ============================================================================

  @doc """
  Declares a package resource for installation or removal.

  Packages are managed idempotently - the provider checks current state
  before taking any action.

  ## States

    * `:installed` - Ensure package is installed (default)
    * `:absent` - Ensure package is removed
    * `:latest` - Ensure package is latest version

  ## Options

    * `:state` - Desired package state (default: `:installed`)
    * `:version` - Specific version to install
    * `:notify` - Handler to trigger on change
    * `:when` - Condition for execution

  ## Examples

      package "nginx"
      package "nginx", state: :installed
      package "nginx", state: :latest
      package "nginx", version: "1.24.0"
      package "nginx", state: :absent
      package "nginx", notify: :restart_web

  """
  defmacro package(name, opts \\ []) do
    transformed_opts = transform_when_option(opts)

    quote do
      unquote(__MODULE__).do_package(unquote(name), unquote(transformed_opts))
    end
  end

  def do_package(name, opts) when is_binary(name) and is_list(opts) do
    task = Process.get(:nexus_current_task)

    if is_nil(task) do
      raise ArgumentError, "package must be called inside a task block"
    end

    alias Nexus.Resources.Types.Package
    resource = Package.new(name, opts)
    updated_task = %{task | commands: task.commands ++ [resource]}
    Process.put(:nexus_current_task, updated_task)
    :ok
  end

  @doc """
  Declares a service resource for management.

  Services are managed idempotently - the provider checks current state
  before taking any action.

  ## States

    * `:running` - Ensure service is running (default)
    * `:stopped` - Ensure service is stopped

  ## Options

    * `:state` - Desired service state (default: `:running`)
    * `:enabled` - Whether service starts on boot (default: `true`)
    * `:action` - One-time action (`:restart`, `:reload`)
    * `:notify` - Handler to trigger on change
    * `:when` - Condition for execution

  ## Examples

      service "nginx"
      service "nginx", state: :running, enabled: true
      service "nginx", action: :restart
      service "nginx", action: :reload, notify: :check_health
      service "nginx", state: :stopped, enabled: false

  """
  defmacro service(name, opts \\ []) do
    transformed_opts = transform_when_option(opts)

    quote do
      unquote(__MODULE__).do_service(unquote(name), unquote(transformed_opts))
    end
  end

  def do_service(name, opts) when is_binary(name) and is_list(opts) do
    task = Process.get(:nexus_current_task)

    if is_nil(task) do
      raise ArgumentError, "service must be called inside a task block"
    end

    alias Nexus.Resources.Types.Service
    resource = Service.new(name, opts)
    updated_task = %{task | commands: task.commands ++ [resource]}
    Process.put(:nexus_current_task, updated_task)
    :ok
  end

  @doc """
  Declares a file resource for creation or management.

  Files are managed idempotently - content, ownership, and permissions
  are checked before any changes are made.

  ## Options

    * `:state` - `:present` or `:absent` (default: `:present`)
    * `:content` - Inline content string
    * `:source` - Local file to upload
    * `:owner` - Owner user (e.g., "root")
    * `:group` - Owner group (e.g., "wheel")
    * `:mode` - File permissions (e.g., `0o644`)
    * `:template` - If true, render source as EEx template
    * `:vars` - Variables for template rendering
    * `:notify` - Handler to trigger on change
    * `:when` - Condition for execution

  ## Examples

      file "/etc/motd", content: "Welcome to the server"
      file "/etc/app.conf", source: "templates/app.conf"
      file "/etc/app.conf",
        source: "templates/app.conf.eex",
        template: true,
        vars: %{port: 8080}
      file "/etc/nginx/nginx.conf",
        source: "nginx.conf",
        owner: "root",
        mode: 0o644,
        notify: :reload_nginx
      file "/tmp/old_file", state: :absent

  """
  defmacro file(path, opts \\ []) do
    transformed_opts = transform_when_option(opts)

    quote do
      unquote(__MODULE__).do_file(unquote(path), unquote(transformed_opts))
    end
  end

  def do_file(path, opts) when is_binary(path) and is_list(opts) do
    task = Process.get(:nexus_current_task)

    if is_nil(task) do
      raise ArgumentError, "file must be called inside a task block"
    end

    alias Nexus.Resources.Types.File, as: FileType
    resource = FileType.new(path, opts)
    updated_task = %{task | commands: task.commands ++ [resource]}
    Process.put(:nexus_current_task, updated_task)
    :ok
  end

  @doc """
  Declares a directory resource for creation or management.

  Directories are managed idempotently - ownership and permissions
  are checked before any changes are made.

  ## Options

    * `:state` - `:present` or `:absent` (default: `:present`)
    * `:owner` - Owner user (e.g., "root")
    * `:group` - Owner group (e.g., "wheel")
    * `:mode` - Directory permissions (e.g., `0o755`)
    * `:recursive` - Create parent directories (default: `true`)
    * `:notify` - Handler to trigger on change
    * `:when` - Condition for execution

  ## Examples

      directory "/var/app"
      directory "/etc/app.d", owner: "root", mode: 0o755
      directory "/opt/myapp/data",
        owner: "deploy",
        group: "deploy",
        mode: 0o750
      directory "/tmp/old_dir", state: :absent

  """
  defmacro directory(path, opts \\ []) do
    transformed_opts = transform_when_option(opts)

    quote do
      unquote(__MODULE__).do_directory(unquote(path), unquote(transformed_opts))
    end
  end

  def do_directory(path, opts) when is_binary(path) and is_list(opts) do
    task = Process.get(:nexus_current_task)

    if is_nil(task) do
      raise ArgumentError, "directory must be called inside a task block"
    end

    alias Nexus.Resources.Types.Directory
    resource = Directory.new(path, opts)
    updated_task = %{task | commands: task.commands ++ [resource]}
    Process.put(:nexus_current_task, updated_task)
    :ok
  end

  @doc """
  Declares a user resource for creation or management.

  Users are managed idempotently - existence and properties are checked
  before any changes are made.

  ## Options

    * `:state` - `:present` or `:absent` (default: `:present`)
    * `:uid` - User ID
    * `:gid` - Primary group ID
    * `:groups` - List of supplementary groups
    * `:home` - Home directory path
    * `:shell` - Login shell
    * `:comment` - GECOS/comment field
    * `:system` - Create as system user (default: `false`)
    * `:notify` - Handler to trigger on change
    * `:when` - Condition for execution

  ## Examples

      user "deploy"
      user "deploy", groups: ["sudo", "docker"]
      user "deploy",
        uid: 1001,
        home: "/home/deploy",
        shell: "/bin/bash",
        groups: ["sudo", "docker"]
      user "olduser", state: :absent

  """
  defmacro user(name, opts \\ []) do
    transformed_opts = transform_when_option(opts)

    quote do
      unquote(__MODULE__).do_user(unquote(name), unquote(transformed_opts))
    end
  end

  def do_user(name, opts) when is_binary(name) and is_list(opts) do
    task = Process.get(:nexus_current_task)

    if is_nil(task) do
      raise ArgumentError, "user must be called inside a task block"
    end

    alias Nexus.Resources.Types.User
    resource = User.new(name, opts)
    updated_task = %{task | commands: task.commands ++ [resource]}
    Process.put(:nexus_current_task, updated_task)
    :ok
  end

  # Group resource - when name is a string, it's a user/system group resource
  # (The @doc for group/2 is defined above with the host group variant)
  # Group resources are for managing system groups, not host groups.
  #
  # Examples:
  #     group "developers"
  #     group "developers", gid: 1001
  #     group "app", system: true
  #     group "oldgroup", state: :absent
  defmacro group(name, opts) when is_binary(name) do
    transformed_opts = transform_when_option(opts)

    quote do
      unquote(__MODULE__).do_group_resource(unquote(name), unquote(transformed_opts))
    end
  end

  def do_group_resource(name, opts) when is_binary(name) and is_list(opts) do
    task = Process.get(:nexus_current_task)

    if is_nil(task) do
      raise ArgumentError, "group (resource) must be called inside a task block"
    end

    alias Nexus.Resources.Types.Group
    resource = Group.new(name, opts)
    updated_task = %{task | commands: task.commands ++ [resource]}
    Process.put(:nexus_current_task, updated_task)
    :ok
  end

  @doc """
  Declares a command resource with idempotency guards.

  Unlike the basic `run` command, the `command` resource supports
  idempotency guards that prevent unnecessary execution.

  ## Idempotency Guards

    * `:creates` - Skip if this path exists
    * `:removes` - Skip if this path doesn't exist
    * `:unless` - Skip if this command succeeds (exit 0)
    * `:onlyif` - Only run if this command succeeds (exit 0)

  ## Options

    * `:creates` - Path that should exist after (skip if exists)
    * `:removes` - Path that should be gone after (skip if absent)
    * `:unless` - Check command (skip if succeeds)
    * `:onlyif` - Check command (run only if succeeds)
    * `:sudo` - Run with sudo (default: `false`)
    * `:user` - Run as specific user
    * `:cwd` - Working directory
    * `:env` - Environment variables map
    * `:timeout` - Timeout in ms (default: `60_000`)
    * `:notify` - Handler to trigger on change
    * `:when` - Condition for execution

  ## Examples

      # Always runs (like traditional run)
      command "echo hello"

      # Idempotent - only runs if target doesn't exist
      command "tar -xzf app.tar.gz", creates: "/opt/app/bin/app"

      # Only runs if deps need updating
      command "mix deps.get",
        unless: "mix deps.check",
        cwd: "/opt/app"

      # With sudo and environment
      command "mix release",
        sudo: true,
        env: %{"MIX_ENV" => "prod"},
        cwd: "/opt/app"

  """
  defmacro command(cmd, opts \\ []) do
    transformed_opts = transform_when_option(opts)

    quote do
      unquote(__MODULE__).do_command(unquote(cmd), unquote(transformed_opts))
    end
  end

  def do_command(cmd, opts) when is_binary(cmd) and is_list(opts) do
    task = Process.get(:nexus_current_task)

    if is_nil(task) do
      raise ArgumentError, "command must be called inside a task block"
    end

    alias Nexus.Resources.Types.Command
    resource = Command.new(cmd, opts)
    updated_task = %{task | commands: task.commands ++ [resource]}
    Process.put(:nexus_current_task, updated_task)
    :ok
  end
end

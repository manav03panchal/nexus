defmodule Nexus.CLI.Init do
  @moduledoc """
  Handles the `nexus init` command.

  Creates a template nexus.exs configuration file with examples
  and documentation.
  """

  @doc """
  Executes the init command with parsed arguments.
  """
  def execute(parsed) do
    output_path = parsed.options[:output]
    force = parsed.flags[:force] || false

    if File.exists?(output_path) && !force do
      IO.puts(:stderr, "Error: File already exists: #{output_path}")
      IO.puts(:stderr, "Use --force to overwrite")
      {:error, 1}
    else
      case write_template(output_path) do
        :ok ->
          IO.puts("Created: #{output_path}")
          IO.puts("")
          IO.puts("Next steps:")
          IO.puts("  1. Edit #{output_path} to define your tasks and hosts")
          IO.puts("  2. Run 'nexus validate' to check your configuration")
          IO.puts("  3. Run 'nexus list' to see defined tasks")
          IO.puts("  4. Run 'nexus run <task>' to execute a task")
          {:ok, 0}

        {:error, reason} ->
          IO.puts(:stderr, "Error: Failed to write file: #{inspect(reason)}")
          {:error, 1}
      end
    end
  end

  defp write_template(path) do
    File.write(path, template())
  end

  defp template do
    ~S"""
    # Nexus Configuration
    # ===================
    #
    # This file defines tasks, hosts, and groups for Nexus.
    # Run `nexus validate` to check this configuration.
    # Run `nexus list` to see all defined tasks.
    # Run `nexus run <task>` to execute a task.

    # Configuration
    # -------------
    # Global settings for Nexus execution.

    config do
      # Default timeout for commands (in milliseconds)
      timeout 30_000

      # Number of retries for failed commands
      retries 0

      # Delay between retries (in milliseconds)
      retry_delay 1_000

      # Stop execution on first failure
      fail_fast true
    end

    # Hosts
    # -----
    # Define remote hosts for task execution.
    # Hosts can be referenced by name in tasks.

    # Example: Simple host definition
    # host :web1, "web1.example.com"

    # Example: Host with user
    # host :web2, "deploy@web2.example.com"

    # Example: Host with user and port
    # host :web3, "deploy@web3.example.com:2222"

    # Example: Host with explicit options
    # host :db1 do
    #   hostname "db1.example.com"
    #   user "admin"
    #   port 22
    # end

    # Groups
    # ------
    # Group hosts together for parallel execution.

    # Example: Web server group
    # group :web, [:web1, :web2, :web3]

    # Example: Database group
    # group :database, [:db1, :db2]

    # Tasks
    # -----
    # Define tasks with commands to execute.

    # Example: Local task with no dependencies
    task :build do
      run "echo 'Building project...'"
      run "mix compile"
    end

    # Example: Task with dependencies
    task :test, deps: [:build] do
      run "mix test"
    end

    # Example: Task running on a specific host
    # task :deploy, deps: [:test], on: :web1 do
    #   run "cd /app && git pull"
    #   run "mix deps.get --only prod"
    #   run "MIX_ENV=prod mix compile"
    # end

    # Example: Task running on a group of hosts (parallel)
    # task :restart, deps: [:deploy], on: :web, strategy: :parallel do
    #   run "sudo systemctl restart myapp", sudo: true
    # end

    # Example: Task with retries and timeout
    # task :health_check, deps: [:restart] do
    #   run "curl -f http://localhost:4000/health", retries: 3, timeout: 10_000
    # end

    # Example: Task that continues on error
    # task :cleanup, deps: [:health_check] do
    #   run "rm -rf /tmp/build-*", continue_on_error: true
    # end

    # Environment Variables
    # ---------------------
    # Use env() to read environment variables:
    #
    # host :production, env("PRODUCTION_HOST")
    #
    # task :deploy, on: :production do
    #   run "echo Deploying as #{env("DEPLOY_USER")}"
    # end
    """
  end
end

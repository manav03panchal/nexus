defmodule Nexus.DSL.ParserTest do
  use ExUnit.Case, async: true

  alias Nexus.DSL.Parser
  alias Nexus.Types.Config

  @moduletag :unit

  describe "parse_string/1" do
    test "parses empty config" do
      assert {:ok, %Config{}} = Parser.parse_string("")
    end

    test "parses config block" do
      dsl = """
      config :nexus,
        default_user: "deploy",
        default_port: 2222,
        connect_timeout: 30_000
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert config.default_user == "deploy"
      assert config.default_port == 2222
      assert config.connect_timeout == 30_000
    end

    test "parses host definitions" do
      dsl = """
      host :web1, "web1.example.com"
      host :web2, "deploy@web2.example.com"
      host :web3, "admin@web3.example.com:2222"
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert Map.has_key?(config.hosts, :web1)
      assert Map.has_key?(config.hosts, :web2)
      assert Map.has_key?(config.hosts, :web3)

      assert config.hosts[:web1].hostname == "web1.example.com"
      assert config.hosts[:web2].user == "deploy"
      assert config.hosts[:web3].port == 2222
    end

    test "parses group definitions" do
      dsl = """
      host :web1, "web1.example.com"
      host :web2, "web2.example.com"
      group :web, [:web1, :web2]
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert Map.has_key?(config.groups, :web)
      assert config.groups[:web].hosts == [:web1, :web2]
    end

    test "parses simple task" do
      dsl = """
      task :build do
        run "mix deps.get"
        run "mix compile"
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert Map.has_key?(config.tasks, :build)

      task = config.tasks[:build]
      assert task.name == :build
      assert task.on == :local
      assert length(task.commands) == 2
      assert Enum.at(task.commands, 0).cmd == "mix deps.get"
      assert Enum.at(task.commands, 1).cmd == "mix compile"
    end

    test "parses task with dependencies" do
      dsl = """
      task :build do
        run "mix compile"
      end

      task :test, deps: [:build] do
        run "mix test"
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert config.tasks[:test].deps == [:build]
    end

    test "parses task with host target" do
      dsl = """
      host :web1, "example.com"
      group :web, [:web1]

      task :deploy, on: :web do
        run "git pull"
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert config.tasks[:deploy].on == :web
    end

    test "parses task with strategy" do
      dsl = """
      host :web1, "example.com"

      task :restart, on: :web1, strategy: :serial do
        run "systemctl restart app"
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert config.tasks[:restart].strategy == :serial
    end

    test "parses run with options" do
      dsl = """
      task :deploy do
        run "apt update", sudo: true
        run "deploy.sh", timeout: 120_000, retries: 3
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      commands = config.tasks[:deploy].commands

      assert Enum.at(commands, 0).sudo == true
      assert Enum.at(commands, 1).timeout == 120_000
      assert Enum.at(commands, 1).retries == 3
    end

    test "applies default_user to hosts without user" do
      dsl = """
      config :nexus, default_user: "deploy"

      host :web1, "web1.example.com"
      host :web2, "admin@web2.example.com"
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      # web1 should get the default user
      assert config.hosts[:web1].user == "deploy"
      # web2 already has a user, should keep it
      assert config.hosts[:web2].user == "admin"
    end

    test "parses env() function calls" do
      System.put_env("TEST_USER", "testdeploy")

      dsl = """
      config :nexus, default_user: env("TEST_USER")
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert config.default_user == "testdeploy"

      System.delete_env("TEST_USER")
    end

    test "env() returns empty string for missing variable" do
      dsl = """
      config :nexus, default_user: env("NONEXISTENT_VAR_12345")
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert config.default_user == ""
    end

    test "returns error for syntax errors" do
      dsl = """
      task :broken do
        this is not valid elixir
      end
      """

      # Capture IO to suppress expected compiler warnings from Code.eval_string
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        send(self(), Parser.parse_string(dsl))
      end)

      assert_receive {:error, message}
      assert message =~ "syntax error" or message =~ "error"
    end

    test "returns error for unknown config options" do
      dsl = """
      config :nexus, unknown_option: "value"
      """

      assert {:error, message} = Parser.parse_string(dsl)
      assert message =~ "unknown config option"
    end

    test "returns error for run outside task block" do
      dsl = """
      run "echo hello"
      """

      assert {:error, message} = Parser.parse_string(dsl)
      assert message =~ "run must be called inside a task block"
    end
  end

  describe "parse_file/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      file_path = Path.join(tmp_dir, "test_nexus_#{:rand.uniform(100_000)}.exs")
      on_exit(fn -> File.rm(file_path) end)
      {:ok, file_path: file_path}
    end

    test "parses file successfully", %{file_path: file_path} do
      content = """
      host :web1, "example.com"

      task :build do
        run "mix compile"
      end
      """

      File.write!(file_path, content)
      assert {:ok, config} = Parser.parse_file(file_path)
      assert Map.has_key?(config.hosts, :web1)
      assert Map.has_key?(config.tasks, :build)
    end

    test "returns error for missing file" do
      assert {:error, message} = Parser.parse_file("/nonexistent/path/nexus.exs")
      assert message =~ "failed to read file"
    end
  end

  describe "complex configurations" do
    test "parses full deployment configuration" do
      dsl = """
      config :nexus,
        default_user: "deploy",
        connect_timeout: 30_000,
        max_connections: 10

      host :web1, "web1.prod.example.com"
      host :web2, "web2.prod.example.com"
      host :db, "admin@db.prod.example.com:2222"

      group :web, [:web1, :web2]
      group :all, [:web1, :web2, :db]

      task :build do
        run "mix deps.get"
        run "mix compile"
      end

      task :test, deps: [:build] do
        run "mix test"
      end

      task :deploy, deps: [:test], on: :web do
        run "git pull"
        run "mix deps.get --only prod"
        run "MIX_ENV=prod mix compile"
        run "sudo systemctl restart app", sudo: true
      end

      task :rolling_restart, on: :web, strategy: :serial do
        run "sudo systemctl restart app", sudo: true
        run "sleep 10"
        run "curl -f http://localhost:4000/health", retries: 3, retry_delay: 5_000
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)

      # Config
      assert config.default_user == "deploy"
      assert config.connect_timeout == 30_000
      assert config.max_connections == 10

      # Hosts
      assert map_size(config.hosts) == 3
      assert config.hosts[:web1].user == "deploy"
      assert config.hosts[:db].port == 2222

      # Groups
      assert map_size(config.groups) == 2
      assert length(config.groups[:all].hosts) == 3

      # Tasks
      assert map_size(config.tasks) == 4
      assert config.tasks[:deploy].deps == [:test]
      assert config.tasks[:rolling_restart].strategy == :serial

      # Commands
      deploy_cmds = config.tasks[:deploy].commands
      assert length(deploy_cmds) == 4
      assert Enum.at(deploy_cmds, 3).sudo == true
    end
  end
end

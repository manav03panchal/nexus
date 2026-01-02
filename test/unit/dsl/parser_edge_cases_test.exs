defmodule Nexus.DSL.ParserEdgeCasesTest do
  use ExUnit.Case, async: true

  alias Nexus.DSL.Parser

  @moduletag :unit

  describe "task definition edge cases" do
    test "task with empty block" do
      dsl = """
      task :empty do
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert config.tasks[:empty].commands == []
    end

    test "task with only comments" do
      dsl = """
      task :commented do
        # This is a comment
        # Another comment
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert config.tasks[:commented].commands == []
    end

    test "task with all options" do
      dsl = """
      host :web1, "web1.example.com"
      group :web, [:web1]

      task :full_options, deps: [:build], on: :web, strategy: :rolling, timeout: 600_000 do
        run "echo test"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      task = config.tasks[:full_options]
      assert task.deps == [:build]
      assert task.on == :web
      assert task.strategy == :rolling
      assert task.timeout == 600_000
    end

    test "task with batch_size for rolling" do
      dsl = """
      host :web1, "web1.example.com"

      task :rolling_deploy, on: :web1, strategy: :rolling, batch_size: 5 do
        run "echo deploy"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      task = config.tasks[:rolling_deploy]
      assert task.batch_size == 5
    end

    test "multiple tasks with dependencies" do
      dsl = """
      task :first do
        run "echo first"
      end

      task :second, deps: [:first] do
        run "echo second"
      end

      task :third, deps: [:first, :second] do
        run "echo third"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert config.tasks[:second].deps == [:first]
      assert config.tasks[:third].deps == [:first, :second]
    end
  end

  describe "run command edge cases" do
    test "run with empty string" do
      dsl = """
      task :empty_cmd do
        run ""
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert Enum.at(config.tasks[:empty_cmd].commands, 0).cmd == ""
    end

    test "run with multiline command" do
      dsl = """
      task :multiline do
        run "echo line1 && \\
             echo line2"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:multiline].commands, 0).cmd
      assert cmd =~ "echo line1"
    end

    test "run with all options" do
      dsl = """
      task :full_run do
        run "command", sudo: true, timeout: 120_000, retries: 3, retry_delay: 5_000
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:full_run].commands, 0)
      assert cmd.sudo == true
      assert cmd.timeout == 120_000
      assert cmd.retries == 3
      assert cmd.retry_delay == 5_000
    end

    test "run with shell special characters" do
      dsl = """
      task :special do
        run "echo $HOME && cat /etc/passwd | grep root"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:special].commands, 0).cmd
      assert cmd =~ "$HOME"
      assert cmd =~ "|"
    end

    test "run with heredoc" do
      dsl = """
      task :heredoc do
        run "cat << 'EOF'\\nline1\\nline2\\nEOF"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert config.tasks[:heredoc] != nil
    end
  end

  describe "host definition edge cases" do
    test "host with just hostname" do
      dsl = """
      host :simple, "example.com"
      """

      {:ok, config} = Parser.parse_string(dsl)
      host = config.hosts[:simple]
      assert host.hostname == "example.com"
      assert host.port == 22
    end

    test "host with user" do
      dsl = """
      host :with_user, "deploy@example.com"
      """

      {:ok, config} = Parser.parse_string(dsl)
      host = config.hosts[:with_user]
      assert host.user == "deploy"
      assert host.hostname == "example.com"
    end

    test "host with user and port" do
      dsl = """
      host :full, "admin@example.com:2222"
      """

      {:ok, config} = Parser.parse_string(dsl)
      host = config.hosts[:full]
      assert host.user == "admin"
      assert host.hostname == "example.com"
      assert host.port == 2222
    end

    test "host with IP address" do
      dsl = """
      host :ip, "192.168.1.100"
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert config.hosts[:ip].hostname == "192.168.1.100"
    end

    test "host with IPv6 returns error (not currently supported)" do
      dsl = """
      host :ipv6, "[::1]"
      """

      # IPv6 format is not currently supported by the host parser
      {:error, _} = Parser.parse_string(dsl)
    end

    test "many hosts" do
      hosts = for i <- 1..50, do: "host :web#{i}, \"web#{i}.example.com\""
      dsl = Enum.join(hosts, "\n")

      {:ok, config} = Parser.parse_string(dsl)
      assert map_size(config.hosts) == 50
    end
  end

  describe "group definition edge cases" do
    test "empty group" do
      dsl = """
      group :empty, []
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert config.groups[:empty].hosts == []
    end

    test "group with single host" do
      dsl = """
      host :web1, "web1.example.com"
      group :single, [:web1]
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert config.groups[:single].hosts == [:web1]
    end

    test "group with many hosts" do
      hosts = for i <- 1..20, do: "host :h#{i}, \"h#{i}.example.com\""
      host_refs = for i <- 1..20, do: ":h#{i}"
      dsl = Enum.join(hosts, "\n") <> "\ngroup :many, [#{Enum.join(host_refs, ", ")}]"

      {:ok, config} = Parser.parse_string(dsl)
      assert length(config.groups[:many].hosts) == 20
    end

    test "multiple groups" do
      dsl = """
      host :web1, "web1.example.com"
      host :web2, "web2.example.com"
      host :db1, "db1.example.com"

      group :web, [:web1, :web2]
      group :db, [:db1]
      group :all, [:web1, :web2, :db1]
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert map_size(config.groups) == 3
    end
  end

  describe "upload edge cases" do
    test "upload with minimal options" do
      dsl = """
      host :web1, "example.com"

      task :upload_test, on: :web1 do
        upload "local.txt", "/remote/file.txt"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:upload_test].commands, 0)
      assert cmd.local_path == "local.txt"
      assert cmd.remote_path == "/remote/file.txt"
    end

    test "upload with all options" do
      dsl = """
      host :web1, "example.com"

      handler :restart do
        run "systemctl restart app"
      end

      task :upload_test, on: :web1 do
        upload "local.txt", "/remote/file.txt", sudo: true, mode: 0o644, notify: :restart
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:upload_test].commands, 0)
      assert cmd.sudo == true
      assert cmd.mode == 0o644
      assert cmd.notify == :restart
    end

    test "upload with paths containing spaces" do
      dsl = """
      host :web1, "example.com"

      task :upload_test, on: :web1 do
        upload "local path/file.txt", "/remote path/file.txt"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:upload_test].commands, 0)
      assert cmd.local_path == "local path/file.txt"
    end
  end

  describe "download edge cases" do
    test "download with minimal options" do
      dsl = """
      host :web1, "example.com"

      task :download_test, on: :web1 do
        download "/remote/file.txt", "local.txt"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:download_test].commands, 0)
      assert cmd.remote_path == "/remote/file.txt"
      assert cmd.local_path == "local.txt"
    end

    test "download with sudo" do
      dsl = """
      host :web1, "example.com"

      task :download_test, on: :web1 do
        download "/etc/shadow", "shadow.bak", sudo: true
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:download_test].commands, 0)
      assert cmd.sudo == true
    end
  end

  describe "template edge cases" do
    test "template with minimal options" do
      dsl = """
      host :web1, "example.com"

      task :template_test, on: :web1 do
        template "app.conf.eex", "/etc/app.conf"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:template_test].commands, 0)
      assert cmd.source == "app.conf.eex"
      assert cmd.destination == "/etc/app.conf"
    end

    test "template with all options" do
      dsl = """
      host :web1, "example.com"

      handler :reload do
        run "systemctl reload app"
      end

      task :template_test, on: :web1 do
        template "app.conf.eex", "/etc/app.conf",
          vars: %{port: 8080, workers: 4},
          sudo: true,
          mode: 0o644,
          notify: :reload
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:template_test].commands, 0)
      assert cmd.vars == %{port: 8080, workers: 4}
      assert cmd.sudo == true
      assert cmd.mode == 0o644
      assert cmd.notify == :reload
    end

    test "template with empty vars" do
      dsl = """
      host :web1, "example.com"

      task :template_test, on: :web1 do
        template "app.conf.eex", "/etc/app.conf", vars: %{}
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:template_test].commands, 0)
      assert cmd.vars == %{}
    end
  end

  describe "wait_for edge cases" do
    test "wait_for http minimal" do
      dsl = """
      host :web1, "example.com"

      task :health_check, on: :web1 do
        wait_for :http, "http://localhost:4000/health"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:health_check].commands, 0)
      assert cmd.type == :http
      assert cmd.target == "http://localhost:4000/health"
    end

    test "wait_for tcp" do
      dsl = """
      host :db1, "example.com"

      task :db_check, on: :db1 do
        wait_for :tcp, "localhost:5432", timeout: 30_000
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:db_check].commands, 0)
      assert cmd.type == :tcp
      assert cmd.timeout == 30_000
    end

    test "wait_for command" do
      dsl = """
      host :web1, "example.com"

      task :process_check, on: :web1 do
        wait_for :command, "pgrep -x nginx"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:process_check].commands, 0)
      assert cmd.type == :command
      assert cmd.target == "pgrep -x nginx"
    end

    test "wait_for with all options" do
      dsl = """
      host :web1, "example.com"

      task :health_check, on: :web1 do
        wait_for :http, "http://localhost:4000/health",
          timeout: 120_000,
          interval: 10_000,
          expected_status: 200,
          expected_body: "OK"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      cmd = Enum.at(config.tasks[:health_check].commands, 0)
      assert cmd.timeout == 120_000
      assert cmd.interval == 10_000
      assert cmd.expected_status == 200
      assert cmd.expected_body == "OK"
    end
  end

  describe "handler edge cases" do
    test "handler with single command" do
      dsl = """
      handler :restart_nginx do
        run "systemctl restart nginx", sudo: true
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      handler = config.handlers[:restart_nginx]
      assert handler.name == :restart_nginx
      assert length(handler.commands) == 1
    end

    test "handler with multiple commands" do
      dsl = """
      handler :full_restart do
        run "systemctl stop app", sudo: true
        run "systemctl stop nginx", sudo: true
        run "systemctl start nginx", sudo: true
        run "systemctl start app", sudo: true
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      handler = config.handlers[:full_restart]
      assert length(handler.commands) == 4
    end

    test "handler with empty block" do
      dsl = """
      handler :noop do
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      handler = config.handlers[:noop]
      assert handler.commands == []
    end

    test "multiple handlers" do
      dsl = """
      handler :restart_nginx do
        run "systemctl restart nginx", sudo: true
      end

      handler :restart_app do
        run "systemctl restart app", sudo: true
      end

      handler :clear_cache do
        run "redis-cli FLUSHALL"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert map_size(config.handlers) == 3
    end
  end

  describe "config edge cases" do
    test "empty config" do
      {:ok, config} = Parser.parse_string("")
      assert config.hosts == %{}
      assert config.groups == %{}
      assert config.tasks == %{}
    end

    test "config with only whitespace" do
      {:ok, config} = Parser.parse_string("   \n\n\t\t\n   ")
      assert config.hosts == %{}
    end

    test "config with only comments" do
      dsl = """
      # This is a comment
      # Another comment
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert config.hosts == %{}
    end

    test "config block with all options" do
      dsl = """
      config :nexus,
        default_user: "deploy",
        default_port: 2222,
        connect_timeout: 60_000,
        command_timeout: 120_000,
        max_connections: 20,
        continue_on_error: true
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert config.default_user == "deploy"
      assert config.default_port == 2222
      assert config.connect_timeout == 60_000
      assert config.command_timeout == 120_000
      assert config.max_connections == 20
      assert config.continue_on_error == true
    end
  end

  describe "env() function edge cases" do
    test "env with existing variable" do
      System.put_env("NEXUS_TEST_VAR", "test_value")

      dsl = """
      config :nexus, default_user: env("NEXUS_TEST_VAR")
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert config.default_user == "test_value"

      System.delete_env("NEXUS_TEST_VAR")
    end

    test "env with missing variable returns empty string" do
      dsl = """
      config :nexus, default_user: env("NONEXISTENT_VAR_XYZ_123")
      """

      {:ok, config} = Parser.parse_string(dsl)
      assert config.default_user == ""
    end
  end

  describe "mixed command types" do
    test "task with all command types" do
      dsl = """
      host :web1, "example.com"

      handler :restart do
        run "systemctl restart app", sudo: true
      end

      task :full_deploy, on: :web1 do
        run "git pull"
        upload "config.json", "/etc/app/config.json", notify: :restart
        template "app.conf.eex", "/etc/app/app.conf", vars: %{port: 8080}
        run "systemctl restart app", sudo: true
        wait_for :http, "http://localhost:8080/health", timeout: 60_000
        download "/var/log/app.log", "deploy.log"
      end
      """

      {:ok, config} = Parser.parse_string(dsl)
      task = config.tasks[:full_deploy]
      assert length(task.commands) == 6
    end
  end

  describe "error handling" do
    test "syntax error returns error tuple" do
      dsl = """
      task :broken do
        run "unclosed string
      end
      """

      result = Parser.parse_string(dsl)
      assert match?({:error, _}, result)
    end

    test "unknown config option returns error" do
      dsl = """
      config :nexus, unknown_option: "value"
      """

      result = Parser.parse_string(dsl)
      assert match?({:error, _}, result)
    end

    test "run outside block returns error" do
      dsl = """
      run "orphaned command"
      """

      result = Parser.parse_string(dsl)
      assert match?({:error, _}, result)
    end

    test "upload outside block returns error" do
      dsl = """
      upload "local", "remote"
      """

      result = Parser.parse_string(dsl)
      assert match?({:error, _}, result)
    end

    test "download outside block returns error" do
      dsl = """
      download "remote", "local"
      """

      result = Parser.parse_string(dsl)
      assert match?({:error, _}, result)
    end

    test "template outside block returns error" do
      dsl = """
      template "source", "dest"
      """

      result = Parser.parse_string(dsl)
      assert match?({:error, _}, result)
    end

    test "wait_for outside block returns error" do
      dsl = """
      wait_for :http, "http://localhost/health"
      """

      result = Parser.parse_string(dsl)
      assert match?({:error, _}, result)
    end
  end
end

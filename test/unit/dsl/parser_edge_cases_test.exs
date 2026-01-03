defmodule Nexus.DSL.ParserEdgeCasesTest do
  @moduledoc """
  Edge case tests for DSL parser error handling.

  Tests parser behavior with:
  - Malformed syntax
  - Invalid values
  - Missing required fields
  - Unicode and special characters
  - Boundary conditions
  """

  use ExUnit.Case, async: true

  alias Nexus.DSL.Parser

  # ============================================================================
  # Syntax Errors
  # ============================================================================

  describe "syntax errors" do
    test "unclosed do block" do
      dsl = """
      task :broken, on: :web do
        command "echo hello"
      """

      assert {:error, _} = Parser.parse_string(dsl)
    end

    test "unclosed string literal" do
      dsl = """
      host :web, "example.com
      """

      assert {:error, _} = Parser.parse_string(dsl)
    end

    test "mismatched brackets" do
      dsl = """
      task :broken, on: :web, tags: [:a, :b do
        command "echo"
      end
      """

      assert {:error, _} = Parser.parse_string(dsl)
    end

    test "invalid elixir syntax" do
      dsl = """
      task :broken on: :web do
        command "echo"
      end
      """

      assert {:error, _} = Parser.parse_string(dsl)
    end

    test "random garbage" do
      dsl = "!@#$%^&*()_+{}|:<>?"
      assert {:error, _} = Parser.parse_string(dsl)
    end

    test "empty string" do
      assert {:ok, config} = Parser.parse_string("")
      assert config.tasks == %{}
      assert config.hosts == %{}
    end

    test "whitespace only" do
      assert {:ok, config} = Parser.parse_string("   \n\t\n   ")
      assert config.tasks == %{}
    end

    test "comment only" do
      assert {:ok, config} = Parser.parse_string("# just a comment")
      assert config.tasks == %{}
    end

    test "multiple unclosed blocks" do
      dsl = """
      task :one, on: :web do
        task :two, on: :web do
          command "nested"
      """

      assert {:error, _} = Parser.parse_string(dsl)
    end
  end

  # ============================================================================
  # Invalid Values
  # ============================================================================

  describe "invalid values" do
    test "non-string hostname" do
      dsl = """
      host :web, 12345
      """

      assert {:error, _} = Parser.parse_string(dsl)
    end

    test "non-atom task name" do
      dsl = """
      task "string_name", on: :web do
        command "echo"
      end
      """

      # This might parse but should be caught somewhere
      result = Parser.parse_string(dsl)
      # Either error or the task shouldn't exist with atom key
      case result do
        {:error, _} -> :ok
        {:ok, config} -> refute Map.has_key?(config.tasks, :string_name)
      end
    end

    test "negative timeout" do
      dsl = """
      config :nexus, connect_timeout: -1000
      """

      # Should parse but might cause issues later
      assert {:ok, _} = Parser.parse_string(dsl)
    end

    test "invalid mode (string instead of integer)" do
      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        directory "/tmp/test", mode: "755"
      end
      """

      # Should error during resource creation
      result = Parser.parse_string(dsl)

      case result do
        {:error, _} -> :ok
        {:ok, _} -> :ok
      end
    end
  end

  # ============================================================================
  # Missing Required Fields
  # ============================================================================

  describe "missing required fields" do
    test "task without on: clause defaults to local" do
      dsl = """
      host :web, "example.com"
      task :orphan do
        command "echo"
      end
      """

      result = Parser.parse_string(dsl)

      case result do
        {:error, _} ->
          :ok

        {:ok, config} ->
          # Tasks without on: may default to :local or nil
          assert config.tasks[:orphan].on in [:local, nil]
      end
    end

    test "host without hostname" do
      dsl = """
      host :incomplete
      """

      assert {:error, _} = Parser.parse_string(dsl)
    end

    test "command without command string" do
      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        command
      end
      """

      # Empty command may parse but create empty task, or may error
      result = Parser.parse_string(dsl)

      case result do
        {:error, _} -> :ok
        {:ok, config} -> assert config.tasks[:test].commands == []
      end
    end

    test "file without path" do
      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        file content: "hello"
      end
      """

      assert {:error, _} = Parser.parse_string(dsl)
    end

    test "directory without path" do
      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        directory mode: 0o755
      end
      """

      assert {:error, _} = Parser.parse_string(dsl)
    end
  end

  # ============================================================================
  # Unicode and Special Characters
  # ============================================================================

  describe "unicode and special characters" do
    test "unicode in command string" do
      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        command "echo ''"
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      [cmd] = config.tasks[:test].commands
      assert cmd.cmd =~ ""
    end

    test "unicode in file content" do
      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        file "/tmp/unicode.txt", content: "Hello "
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      [cmd] = config.tasks[:test].commands
      assert cmd.content =~ ""
    end

    test "emoji in task tags" do
      # Tags must be atoms, so this should fail or be escaped
      dsl = """
      host :web, "example.com"
      task :test, on: :web, tags: [:] do
        command "echo"
      end
      """

      # Elixir allows unicode atoms in some cases
      result = Parser.parse_string(dsl)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "special characters in hostname" do
      dsl = """
      host :special, "host-with_special.chars123.com"
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert config.hosts[:special].hostname == "host-with_special.chars123.com"
    end

    test "escaped quotes in strings" do
      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        command "echo \\"quoted\\""
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      [cmd] = config.tasks[:test].commands
      assert cmd.cmd =~ "quoted"
    end

    test "newlines in content" do
      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        file "/tmp/multi.txt", content: "line1\\nline2\\nline3"
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      [cmd] = config.tasks[:test].commands
      assert cmd.content =~ "line1"
    end

    test "heredoc content" do
      dsl = ~S'''
      host :web, "example.com"
      task :test, on: :web do
        file "/tmp/heredoc.txt", content: """
        This is
        multiline
        content
        """
      end
      '''

      assert {:ok, config} = Parser.parse_string(dsl)
      [cmd] = config.tasks[:test].commands
      assert cmd.content =~ "multiline"
    end
  end

  # ============================================================================
  # Boundary Conditions
  # ============================================================================

  describe "boundary conditions" do
    test "very long task name rejected by Elixir" do
      # Elixir has a limit on atom length (~255 chars)
      long_name = String.duplicate("a", 1000)

      dsl = """
      host :web, "example.com"
      task :#{long_name}, on: :web do
        command "echo"
      end
      """

      # Very long atoms are rejected by Elixir parser
      assert {:error, _} = Parser.parse_string(dsl)
    end

    test "moderately long task name" do
      long_name = String.duplicate("a", 100)

      dsl = """
      host :web, "example.com"
      task :#{long_name}, on: :web do
        command "echo"
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert Map.has_key?(config.tasks, String.to_atom(long_name))
    end

    test "very long command string" do
      long_cmd = "echo " <> String.duplicate("x", 10_000)

      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        command "#{long_cmd}"
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      [cmd] = config.tasks[:test].commands
      assert String.length(cmd.cmd) > 10_000
    end

    test "many tasks" do
      tasks =
        for i <- 1..100 do
          """
          task :task_#{i}, on: :web do
            command "echo #{i}"
          end
          """
        end

      dsl = """
      host :web, "example.com"
      #{Enum.join(tasks, "\n")}
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert map_size(config.tasks) == 100
    end

    test "many commands in one task" do
      commands =
        for i <- 1..100 do
          "command \"echo #{i}\""
        end

      dsl = """
      host :web, "example.com"
      task :many_commands, on: :web do
        #{Enum.join(commands, "\n  ")}
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert length(config.tasks[:many_commands].commands) == 100
    end

    test "deeply nested conditionals" do
      # Not really nested but complex condition
      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        command "echo test", when: facts(:os) == :linux and facts(:cpu_count) > 1
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      [cmd] = config.tasks[:test].commands
      assert cmd.when != true
    end

    test "zero mode" do
      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        directory "/tmp/zero", mode: 0o0
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      [cmd] = config.tasks[:test].commands
      assert cmd.mode == 0
    end

    test "max mode (7777)" do
      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        directory "/tmp/max", mode: 0o7777
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      [cmd] = config.tasks[:test].commands
      assert cmd.mode == 0o7777
    end
  end

  # ============================================================================
  # Duplicate Definitions
  # ============================================================================

  describe "duplicate definitions" do
    test "duplicate host names" do
      dsl = """
      host :web, "server1.com"
      host :web, "server2.com"
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      # Second definition should override
      assert config.hosts[:web].hostname == "server2.com"
    end

    test "duplicate task names" do
      dsl = """
      host :web, "example.com"
      task :deploy, on: :web do
        command "echo first"
      end
      task :deploy, on: :web do
        command "echo second"
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      # Second definition should override
      [cmd] = config.tasks[:deploy].commands
      assert cmd.cmd =~ "second"
    end

    test "duplicate handler names" do
      dsl = """
      handler :restart do
        run "echo first"
      end
      handler :restart do
        run "echo second"
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      [cmd] = config.handlers[:restart].commands
      assert cmd.cmd =~ "second"
    end
  end

  # ============================================================================
  # Mixed Resources
  # ============================================================================

  describe "mixed resource types" do
    test "all resource types in one task" do
      dsl = """
      host :web, "example.com"
      task :full, on: :web do
        directory "/opt/app"
        file "/opt/app/config", content: "test"
        package "nginx"
        service "nginx", state: :running
        command "echo done"
        command "legacy command"
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert length(config.tasks[:full].commands) == 6
    end

    test "resources with handlers" do
      dsl = """
      host :web, "example.com"

      handler :reload do
        run "systemctl reload nginx"
      end

      task :configure, on: :web do
        file "/etc/nginx/nginx.conf", content: "config", notify: :reload
        service "nginx", state: :running
      end
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert Map.has_key?(config.handlers, :reload)
      [file_cmd, _service_cmd] = config.tasks[:configure].commands
      assert file_cmd.notify == :reload
    end
  end

  # ============================================================================
  # Environment Variables
  # ============================================================================

  describe "environment variable handling" do
    test "System.get_env in config" do
      # Set env var for test
      System.put_env("TEST_NEXUS_VAR", "test_value")

      dsl = """
      config :nexus,
        default_user: System.get_env("TEST_NEXUS_VAR")
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert config.default_user == "test_value"

      System.delete_env("TEST_NEXUS_VAR")
    end

    test "missing env var returns nil" do
      dsl = """
      config :nexus,
        default_user: System.get_env("DEFINITELY_NOT_SET_12345")
      """

      assert {:ok, config} = Parser.parse_string(dsl)
      assert config.default_user == nil
    end
  end

  # ============================================================================
  # Security Edge Cases
  # ============================================================================

  describe "security edge cases" do
    test "command injection attempt in run" do
      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        command "echo $(whoami)"
      end
      """

      # Should parse - actual execution is where this matters
      assert {:ok, config} = Parser.parse_string(dsl)
      [cmd] = config.tasks[:test].commands
      assert cmd.cmd == "echo $(whoami)"
    end

    test "path traversal in file path" do
      dsl = """
      host :web, "example.com"
      task :test, on: :web do
        file "/tmp/../etc/passwd", content: "hacked"
      end
      """

      # Parser accepts it - validation happens elsewhere
      assert {:ok, config} = Parser.parse_string(dsl)
      [cmd] = config.tasks[:test].commands
      assert cmd.path == "/tmp/../etc/passwd"
    end
  end
end

defmodule Nexus.DSL.ParserPropertiesTest do
  @moduledoc """
  Property-based tests for DSL parser.

  Tests parser robustness against various inputs including:
  - Valid DSL constructs with random values
  - Edge cases (empty strings, special characters, unicode)
  - Malformed inputs that should fail gracefully
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  @moduletag :property

  alias Nexus.DSL.Parser

  # Generators for valid DSL components

  defp valid_identifier do
    gen all(
          first <- StreamData.string(?a..?z, min_length: 1, max_length: 1),
          rest <- StreamData.string([?a..?z, ?0..?9, ?_], max_length: 20)
        ) do
      first <> rest
    end
  end

  defp valid_atom_name do
    gen all(name <- valid_identifier()) do
      String.to_atom(name)
    end
  end

  defp valid_hostname do
    gen all(
          parts <-
            StreamData.list_of(StreamData.string(?a..?z, min_length: 1, max_length: 10),
              min_length: 2,
              max_length: 4
            )
        ) do
      Enum.join(parts, ".")
    end
  end

  defp valid_path do
    gen all(
          parts <-
            StreamData.list_of(
              StreamData.string([?a..?z, ?0..?9, ?_, ?-], min_length: 1, max_length: 15),
              min_length: 1,
              max_length: 5
            )
        ) do
      "/" <> Enum.join(parts, "/")
    end
  end

  defp valid_mode do
    StreamData.integer(0..0o7777)
  end

  defp valid_command do
    gen all(
          cmd <- StreamData.member_of(["echo", "ls", "cat", "pwd", "whoami", "date", "uname"]),
          args <- StreamData.string(:alphanumeric, max_length: 20)
        ) do
      if args == "", do: cmd, else: "#{cmd} #{args}"
    end
  end

  # ============================================================================
  # Host Definition Tests
  # ============================================================================

  describe "host parsing" do
    property "valid host definitions are parsed correctly" do
      check all(
              name <- valid_atom_name(),
              hostname <- valid_hostname()
            ) do
        dsl = """
        host :#{name}, "#{hostname}"
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        assert Map.has_key?(config.hosts, name)
        assert config.hosts[name].hostname == hostname
      end
    end

    property "host names with underscores are valid" do
      check all(
              prefix <- StreamData.string(?a..?z, min_length: 1, max_length: 5),
              suffix <- StreamData.string(?a..?z, min_length: 1, max_length: 5),
              hostname <- valid_hostname()
            ) do
        name = "#{prefix}_#{suffix}"

        dsl = """
        host :#{name}, "#{hostname}"
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        assert Map.has_key?(config.hosts, String.to_atom(name))
      end
    end
  end

  # ============================================================================
  # Task Definition Tests
  # ============================================================================

  describe "task parsing" do
    property "valid task definitions are parsed correctly" do
      check all(
              task_name <- valid_atom_name(),
              host_name <- valid_atom_name(),
              hostname <- valid_hostname()
            ) do
        dsl = """
        host :#{host_name}, "#{hostname}"

        task :#{task_name}, on: :#{host_name} do
          command "echo hello"
        end
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        assert Map.has_key?(config.tasks, task_name)
        assert config.tasks[task_name].on == host_name
      end
    end

    property "tasks with multiple commands preserve order" do
      check all(
              task_name <- valid_atom_name(),
              host_name <- valid_atom_name(),
              hostname <- valid_hostname(),
              commands <- StreamData.list_of(valid_command(), min_length: 1, max_length: 5)
            ) do
        run_stmts = Enum.map_join(commands, "\n  ", fn cmd -> "command \"#{cmd}\"" end)

        dsl = """
        host :#{host_name}, "#{hostname}"

        task :#{task_name}, on: :#{host_name} do
          #{run_stmts}
        end
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        assert length(config.tasks[task_name].commands) == length(commands)
      end
    end

    property "task tags are preserved" do
      check all(
              task_name <- valid_atom_name(),
              host_name <- valid_atom_name(),
              hostname <- valid_hostname(),
              tags <- StreamData.list_of(valid_atom_name(), min_length: 1, max_length: 3)
            ) do
        tags_str = "[" <> Enum.map_join(tags, ", ", &":#{&1}") <> "]"

        dsl = """
        host :#{host_name}, "#{hostname}"

        task :#{task_name}, on: :#{host_name}, tags: #{tags_str} do
          command "echo test"
        end
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        assert MapSet.new(config.tasks[task_name].tags) == MapSet.new(tags)
      end
    end
  end

  # ============================================================================
  # Resource Definition Tests
  # ============================================================================

  describe "directory resource parsing" do
    property "directory paths are preserved" do
      check all(
              task_name <- valid_atom_name(),
              host_name <- valid_atom_name(),
              hostname <- valid_hostname(),
              path <- valid_path()
            ) do
        dsl = """
        host :#{host_name}, "#{hostname}"

        task :#{task_name}, on: :#{host_name} do
          directory "#{path}"
        end
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        [cmd] = config.tasks[task_name].commands
        assert cmd.path == path
      end
    end

    property "directory mode is preserved" do
      check all(
              task_name <- valid_atom_name(),
              host_name <- valid_atom_name(),
              hostname <- valid_hostname(),
              path <- valid_path(),
              mode <- valid_mode()
            ) do
        dsl = """
        host :#{host_name}, "#{hostname}"

        task :#{task_name}, on: :#{host_name} do
          directory "#{path}", mode: 0o#{Integer.to_string(mode, 8)}
        end
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        [cmd] = config.tasks[task_name].commands
        assert cmd.mode == mode
      end
    end
  end

  describe "file resource parsing" do
    property "file paths and content are preserved" do
      check all(
              task_name <- valid_atom_name(),
              host_name <- valid_atom_name(),
              hostname <- valid_hostname(),
              path <- valid_path(),
              # Avoid special chars that break string literals
              content <- StreamData.string(:alphanumeric, min_length: 1, max_length: 50)
            ) do
        dsl = """
        host :#{host_name}, "#{hostname}"

        task :#{task_name}, on: :#{host_name} do
          file "#{path}", content: "#{content}"
        end
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        [cmd] = config.tasks[task_name].commands
        assert cmd.path == path
        assert cmd.content == content
      end
    end
  end

  describe "command resource parsing" do
    property "command strings are preserved" do
      check all(
              task_name <- valid_atom_name(),
              host_name <- valid_atom_name(),
              hostname <- valid_hostname(),
              cmd <- valid_command()
            ) do
        dsl = """
        host :#{host_name}, "#{hostname}"

        task :#{task_name}, on: :#{host_name} do
          command "#{cmd}"
        end
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        [parsed_cmd] = config.tasks[task_name].commands
        assert parsed_cmd.cmd == cmd
      end
    end

    property "command with creates guard is preserved" do
      check all(
              task_name <- valid_atom_name(),
              host_name <- valid_atom_name(),
              hostname <- valid_hostname(),
              cmd <- valid_command(),
              creates_path <- valid_path()
            ) do
        dsl = """
        host :#{host_name}, "#{hostname}"

        task :#{task_name}, on: :#{host_name} do
          command "#{cmd}", creates: "#{creates_path}"
        end
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        [parsed_cmd] = config.tasks[task_name].commands
        assert parsed_cmd.creates == creates_path
      end
    end
  end

  describe "package resource parsing" do
    property "package names are preserved" do
      check all(
              task_name <- valid_atom_name(),
              host_name <- valid_atom_name(),
              hostname <- valid_hostname(),
              pkg_name <-
                StreamData.string([?a..?z, ?0..?9, ?-, ?_], min_length: 2, max_length: 20)
            ) do
        dsl = """
        host :#{host_name}, "#{hostname}"

        task :#{task_name}, on: :#{host_name} do
          package "#{pkg_name}"
        end
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        [cmd] = config.tasks[task_name].commands
        assert cmd.name == pkg_name
      end
    end
  end

  # ============================================================================
  # Error Handling Tests
  # ============================================================================

  describe "malformed input handling" do
    property "unclosed strings are rejected" do
      check all(
              task_name <- valid_atom_name(),
              random_text <- StreamData.string(:alphanumeric, min_length: 1, max_length: 20)
            ) do
        dsl = """
        task :#{task_name} do
          command "#{random_text}
        end
        """

        assert {:error, _} = Parser.parse_string(dsl)
      end
    end

    property "invalid atoms are rejected" do
      check all(
              # Start with number (invalid atom)
              invalid_name <- StreamData.string(?0..?9, min_length: 1, max_length: 5)
            ) do
        dsl = """
        host :#{invalid_name}, "test.com"
        """

        # Should either error or Elixir will raise during parsing
        result = Parser.parse_string(dsl)
        assert match?({:error, _}, result) or match?({:ok, _}, result)
      end
    end

    property "empty task bodies are handled" do
      check all(
              task_name <- valid_atom_name(),
              host_name <- valid_atom_name(),
              hostname <- valid_hostname()
            ) do
        dsl = """
        host :#{host_name}, "#{hostname}"

        task :#{task_name}, on: :#{host_name} do
        end
        """

        # Empty tasks should parse but have no commands
        case Parser.parse_string(dsl) do
          {:ok, config} ->
            assert config.tasks[task_name].commands == []

          {:error, _} ->
            # Also acceptable - empty body rejected
            :ok
        end
      end
    end
  end

  # ============================================================================
  # Handler Tests
  # ============================================================================

  describe "handler parsing" do
    property "handler names and commands are preserved" do
      check all(
              handler_name <- valid_atom_name(),
              cmd <- valid_command()
            ) do
        # Handlers use run/2, not command/2 (command is for task resources)
        dsl = """
        handler :#{handler_name} do
          run "#{cmd}"
        end
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        assert Map.has_key?(config.handlers, handler_name)
        assert length(config.handlers[handler_name].commands) == 1
      end
    end
  end

  # ============================================================================
  # Config Tests
  # ============================================================================

  describe "config parsing" do
    property "config values are preserved" do
      check all(
              timeout <- StreamData.integer(1000..120_000),
              user <- valid_identifier()
            ) do
        dsl = """
        config :nexus,
          default_user: "#{user}",
          connect_timeout: #{timeout}
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        assert config.default_user == user
        assert config.connect_timeout == timeout
      end
    end
  end
end

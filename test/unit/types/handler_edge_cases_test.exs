defmodule Nexus.Types.HandlerEdgeCasesTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.{Command, Config, Handler}

  @moduletag :unit

  describe "handler creation edge cases" do
    test "creates handler with atom name" do
      handler = Handler.new(:restart_nginx)
      assert handler.name == :restart_nginx
      assert handler.commands == []
    end

    test "handler name with underscores" do
      handler = Handler.new(:restart_all_services)
      assert handler.name == :restart_all_services
    end

    test "handler name with numbers" do
      handler = Handler.new(:handler_v2)
      assert handler.name == :handler_v2
    end

    test "single character handler name" do
      handler = Handler.new(:a)
      assert handler.name == :a
    end

    test "very long handler name" do
      long_name = String.duplicate("a", 100) |> String.to_atom()
      handler = Handler.new(long_name)
      assert handler.name == long_name
    end
  end

  describe "adding commands to handlers" do
    test "add single command" do
      handler = Handler.new(:test)
      command = Command.new("echo hello")
      handler = Handler.add_command(handler, command)

      assert length(handler.commands) == 1
      assert Enum.at(handler.commands, 0).cmd == "echo hello"
    end

    test "add multiple commands preserves order" do
      handler = Handler.new(:test)

      handler =
        handler
        |> Handler.add_command(Command.new("step 1"))
        |> Handler.add_command(Command.new("step 2"))
        |> Handler.add_command(Command.new("step 3"))

      assert length(handler.commands) == 3
      assert Enum.at(handler.commands, 0).cmd == "step 1"
      assert Enum.at(handler.commands, 1).cmd == "step 2"
      assert Enum.at(handler.commands, 2).cmd == "step 3"
    end

    test "add many commands" do
      handler = Handler.new(:large_handler)

      handler =
        Enum.reduce(1..50, handler, fn i, h ->
          Handler.add_command(h, Command.new("command #{i}"))
        end)

      assert length(handler.commands) == 50
    end

    test "add command with sudo" do
      handler = Handler.new(:privileged)
      command = Command.new("systemctl restart nginx", sudo: true)
      handler = Handler.add_command(handler, command)

      assert Enum.at(handler.commands, 0).sudo == true
    end

    test "add command with timeout" do
      handler = Handler.new(:slow)
      command = Command.new("slow_script.sh", timeout: 120_000)
      handler = Handler.add_command(handler, command)

      assert Enum.at(handler.commands, 0).timeout == 120_000
    end

    test "add command with retries" do
      handler = Handler.new(:flaky)
      command = Command.new("flaky_command", retries: 3, retry_delay: 5_000)
      handler = Handler.add_command(handler, command)

      assert Enum.at(handler.commands, 0).retries == 3
      assert Enum.at(handler.commands, 0).retry_delay == 5_000
    end
  end

  describe "handler in config" do
    test "add handler to empty config" do
      config = Config.new()
      handler = Handler.new(:restart_nginx)
      handler = Handler.add_command(handler, Command.new("systemctl restart nginx"))

      config = Config.add_handler(config, handler)

      assert Map.has_key?(config.handlers, :restart_nginx)
      assert config.handlers[:restart_nginx].name == :restart_nginx
    end

    test "add multiple handlers" do
      config = Config.new()

      config =
        config
        |> Config.add_handler(Handler.new(:restart_nginx))
        |> Config.add_handler(Handler.new(:restart_app))
        |> Config.add_handler(Handler.new(:clear_cache))

      assert map_size(config.handlers) == 3
    end

    test "overwrite handler with same name" do
      config = Config.new()

      handler1 = Handler.new(:restart) |> Handler.add_command(Command.new("v1"))
      handler2 = Handler.new(:restart) |> Handler.add_command(Command.new("v2"))

      config = Config.add_handler(config, handler1)
      config = Config.add_handler(config, handler2)

      # Second handler should overwrite first
      assert map_size(config.handlers) == 1
      assert Enum.at(config.handlers[:restart].commands, 0).cmd == "v2"
    end

    test "empty config has no handlers" do
      config = Config.new()
      assert config.handlers == %{}
    end
  end

  describe "handler command variations" do
    test "handler with empty commands" do
      handler = Handler.new(:noop)
      assert handler.commands == []
    end

    test "handler with single sudo command" do
      handler =
        Handler.new(:restart)
        |> Handler.add_command(Command.new("systemctl restart app", sudo: true))

      assert length(handler.commands) == 1
      assert Enum.at(handler.commands, 0).sudo == true
    end

    test "handler with mixed sudo commands" do
      handler =
        Handler.new(:mixed)
        |> Handler.add_command(Command.new("echo starting"))
        |> Handler.add_command(Command.new("systemctl restart app", sudo: true))
        |> Handler.add_command(Command.new("echo done"))

      commands = handler.commands
      assert Enum.at(commands, 0).sudo == false
      assert Enum.at(commands, 1).sudo == true
      assert Enum.at(commands, 2).sudo == false
    end

    test "handler with complex command options" do
      handler =
        Handler.new(:complex)
        |> Handler.add_command(
          Command.new("flaky_restart",
            sudo: true,
            timeout: 60_000,
            retries: 3,
            retry_delay: 10_000
          )
        )

      cmd = Enum.at(handler.commands, 0)
      assert cmd.sudo == true
      assert cmd.timeout == 60_000
      assert cmd.retries == 3
      assert cmd.retry_delay == 10_000
    end
  end

  describe "notify pattern edge cases" do
    test "upload with notify creates association" do
      # This tests the pattern, actual integration is in parser tests
      upload_notify = :restart_nginx
      handler = Handler.new(upload_notify)

      assert handler.name == :restart_nginx
    end

    test "multiple uploads can notify same handler" do
      # Multiple uploads can trigger same handler
      handler_name = :reload_config
      handler = Handler.new(handler_name)

      # Each upload would reference the same handler
      assert handler.name == handler_name
    end

    test "handler name matches notify reference" do
      handler = Handler.new(:my_handler)
      notify_reference = :my_handler

      assert handler.name == notify_reference
    end
  end

  describe "handler immutability" do
    test "add_command returns new handler" do
      original = Handler.new(:test)
      command = Command.new("test")
      modified = Handler.add_command(original, command)

      # Original should be unchanged
      assert original.commands == []
      assert length(modified.commands) == 1
    end

    test "multiple modifications create chain" do
      h0 = Handler.new(:chain)
      h1 = Handler.add_command(h0, Command.new("cmd1"))
      h2 = Handler.add_command(h1, Command.new("cmd2"))
      h3 = Handler.add_command(h2, Command.new("cmd3"))

      assert h0.commands == []
      assert length(h1.commands) == 1
      assert length(h2.commands) == 2
      assert length(h3.commands) == 3
    end
  end

  describe "handler struct inspection" do
    test "handler is inspectable" do
      handler =
        Handler.new(:test)
        |> Handler.add_command(Command.new("echo test"))

      inspected = inspect(handler)
      assert inspected =~ "Handler"
      assert inspected =~ ":test"
    end

    test "handler is serializable to map" do
      handler =
        Handler.new(:test)
        |> Handler.add_command(Command.new("echo test"))

      map = Map.from_struct(handler)
      assert map[:name] == :test
      assert is_list(map[:commands])
    end
  end

  describe "handler execution order" do
    test "commands execute in order added" do
      handler =
        Handler.new(:ordered)
        |> Handler.add_command(Command.new("first"))
        |> Handler.add_command(Command.new("second"))
        |> Handler.add_command(Command.new("third"))

      cmds = Enum.map(handler.commands, & &1.cmd)
      assert cmds == ["first", "second", "third"]
    end

    test "enumerable commands" do
      handler =
        Handler.new(:enum_test)
        |> Handler.add_command(Command.new("a"))
        |> Handler.add_command(Command.new("b"))
        |> Handler.add_command(Command.new("c"))

      # Can enumerate commands
      result = Enum.map(handler.commands, fn cmd -> String.upcase(cmd.cmd) end)
      assert result == ["A", "B", "C"]
    end
  end
end

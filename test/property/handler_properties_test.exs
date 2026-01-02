defmodule Nexus.Property.HandlerPropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Nexus.Types.{Command, Config, Handler}

  @moduletag :property

  describe "Handler struct properties" do
    property "handler name is preserved" do
      check all(name <- atom(:alphanumeric)) do
        handler = Handler.new(name)
        assert handler.name == name
      end
    end

    property "new handler has empty commands" do
      check all(name <- atom(:alphanumeric)) do
        handler = Handler.new(name)
        assert handler.commands == []
      end
    end

    property "adding command increases command count by 1" do
      check all(
              name <- atom(:alphanumeric),
              cmd <- string(:printable, min_length: 1, max_length: 100)
            ) do
        handler = Handler.new(name)
        initial_count = length(handler.commands)
        updated = Handler.add_command(handler, Command.new(cmd))
        assert length(updated.commands) == initial_count + 1
      end
    end

    property "commands are added in order" do
      check all(
              name <- atom(:alphanumeric),
              cmds <- list_of(string(:alphanumeric, min_length: 1), min_length: 1, max_length: 10)
            ) do
        handler =
          Enum.reduce(cmds, Handler.new(name), fn cmd, h ->
            Handler.add_command(h, Command.new(cmd))
          end)

        result_cmds = Enum.map(handler.commands, & &1.cmd)
        assert result_cmds == cmds
      end
    end

    property "handler is immutable - original unchanged after add" do
      check all(
              name <- atom(:alphanumeric),
              cmd <- string(:printable, min_length: 1)
            ) do
        original = Handler.new(name)
        _modified = Handler.add_command(original, Command.new(cmd))
        assert original.commands == []
      end
    end
  end

  describe "Handler in Config properties" do
    property "adding handler to config preserves it" do
      check all(name <- atom(:alphanumeric)) do
        config = Config.new()
        handler = Handler.new(name)
        updated = Config.add_handler(config, handler)
        assert Map.has_key?(updated.handlers, name)
        assert updated.handlers[name].name == name
      end
    end

    property "multiple handlers with unique names are preserved" do
      check all(
              names <-
                list_of(atom(:alphanumeric), min_length: 1, max_length: 10)
                |> map(&Enum.uniq/1)
            ) do
        config =
          Enum.reduce(names, Config.new(), fn name, cfg ->
            Config.add_handler(cfg, Handler.new(name))
          end)

        assert map_size(config.handlers) == length(names)
      end
    end

    property "handler with same name overwrites previous" do
      check all(name <- atom(:alphanumeric)) do
        handler1 = Handler.new(name) |> Handler.add_command(Command.new("cmd1"))
        handler2 = Handler.new(name) |> Handler.add_command(Command.new("cmd2"))

        config =
          Config.new()
          |> Config.add_handler(handler1)
          |> Config.add_handler(handler2)

        assert map_size(config.handlers) == 1
        assert Enum.at(config.handlers[name].commands, 0).cmd == "cmd2"
      end
    end
  end

  describe "Command properties in handlers" do
    property "command options are preserved in handler" do
      check all(
              name <- atom(:alphanumeric),
              cmd <- string(:alphanumeric, min_length: 1),
              sudo <- boolean(),
              timeout <- positive_integer()
            ) do
        command = Command.new(cmd, sudo: sudo, timeout: timeout)
        handler = Handler.new(name) |> Handler.add_command(command)
        stored_cmd = Enum.at(handler.commands, 0)
        assert stored_cmd.sudo == sudo
        assert stored_cmd.timeout == timeout
      end
    end

    property "retries option is preserved" do
      check all(
              name <- atom(:alphanumeric),
              cmd <- string(:alphanumeric, min_length: 1),
              retries <- integer(0..10)
            ) do
        command = Command.new(cmd, retries: retries)
        handler = Handler.new(name) |> Handler.add_command(command)
        stored_cmd = Enum.at(handler.commands, 0)
        assert stored_cmd.retries == retries
      end
    end
  end
end

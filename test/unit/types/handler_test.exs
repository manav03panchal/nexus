defmodule Nexus.Types.HandlerTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.{Command, Handler}

  describe "new/1" do
    test "creates handler with name" do
      handler = Handler.new(:restart_nginx)

      assert handler.name == :restart_nginx
      assert handler.commands == []
    end
  end

  describe "add_command/2" do
    test "adds command to handler" do
      handler = Handler.new(:restart_nginx)
      command = Command.new("systemctl restart nginx", sudo: true)

      updated = Handler.add_command(handler, command)

      assert length(updated.commands) == 1
      assert hd(updated.commands).cmd == "systemctl restart nginx"
      assert hd(updated.commands).sudo == true
    end

    test "preserves command order" do
      handler = Handler.new(:reload_app)
      cmd1 = Command.new("systemctl reload app")
      cmd2 = Command.new("sleep 2")
      cmd3 = Command.new("curl localhost/health")

      updated =
        handler
        |> Handler.add_command(cmd1)
        |> Handler.add_command(cmd2)
        |> Handler.add_command(cmd3)

      assert length(updated.commands) == 3
      assert Enum.at(updated.commands, 0).cmd == "systemctl reload app"
      assert Enum.at(updated.commands, 1).cmd == "sleep 2"
      assert Enum.at(updated.commands, 2).cmd == "curl localhost/health"
    end
  end

  describe "struct" do
    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Handler, [])
      end
    end
  end
end

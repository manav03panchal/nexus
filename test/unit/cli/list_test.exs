defmodule Nexus.CLI.ListTest do
  use ExUnit.Case, async: true
  use Nexus.TestCase

  alias Nexus.CLI.List

  @moduletag :unit

  describe "execute/1" do
    setup :tmp_dir

    test "lists tasks from configuration", %{tmp_dir: dir} do
      config_content = """
      task :build do
        run "echo building"
      end

      task :test, deps: [:build] do
        run "echo testing"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, format: :text},
        flags: %{plain: false},
        args: %{}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = List.execute(parsed)
        end)

      assert output =~ "Tasks"
      assert output =~ "build"
      assert output =~ "test"
      assert output =~ "deps: build"
    end

    test "lists hosts from configuration", %{tmp_dir: dir} do
      config_content = """
      host :web1, "web1.example.com"
      host :web2, "deploy@web2.example.com:2222"

      task :deploy, on: :web1 do
        run "echo deploying"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, format: :text},
        flags: %{plain: false},
        args: %{}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = List.execute(parsed)
        end)

      assert output =~ "Hosts"
      assert output =~ "web1"
      assert output =~ "web2"
      assert output =~ "web1.example.com"
      assert output =~ "deploy@web2.example.com:2222"
    end

    test "lists groups from configuration", %{tmp_dir: dir} do
      config_content = """
      host :web1, "web1.example.com"
      host :web2, "web2.example.com"

      group :web, [:web1, :web2]

      task :deploy, on: :web do
        run "echo deploying"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, format: :text},
        flags: %{plain: false},
        args: %{}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = List.execute(parsed)
        end)

      assert output =~ "Groups"
      assert output =~ "web"
      assert output =~ "web1"
      assert output =~ "web2"
    end

    test "outputs JSON format", %{tmp_dir: dir} do
      config_content = """
      host :web1, "web1.example.com"

      task :build do
        run "echo building"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, format: :json},
        flags: %{plain: false},
        args: %{}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = List.execute(parsed)
        end)

      # Should be valid JSON (or inspect format if Jason not available)
      assert output =~ "build" or output =~ ":build"
      assert output =~ "web1" or output =~ ":web1"
    end

    test "reports file not found", %{tmp_dir: dir} do
      path = Path.join(dir, "nonexistent.exs")

      parsed = %{
        options: %{config: path, format: :text},
        flags: %{plain: false},
        args: %{}
      }

      output =
        capture_io(:stderr, fn ->
          assert {:error, 1} = List.execute(parsed)
        end)

      assert output =~ "Config file not found"
    end

    test "shows empty state when no tasks defined", %{tmp_dir: dir} do
      # Create a minimal valid config with just a host (no tasks)
      config_content = """
      host :dummy, "dummy.example.com"
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, format: :text},
        flags: %{plain: false},
        args: %{}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = List.execute(parsed)
        end)

      assert output =~ "No tasks defined"
    end

    test "shows command count for tasks", %{tmp_dir: dir} do
      config_content = """
      task :build do
        run "echo step 1"
        run "echo step 2"
        run "echo step 3"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, format: :text},
        flags: %{plain: false},
        args: %{}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = List.execute(parsed)
        end)

      assert output =~ "3 commands"
    end

    test "shows task execution target", %{tmp_dir: dir} do
      config_content = """
      host :prod, "prod.example.com"

      task :local_task do
        run "echo local"
      end

      task :remote_task, on: :prod do
        run "echo remote"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, format: :text},
        flags: %{plain: false},
        args: %{}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = List.execute(parsed)
        end)

      assert output =~ "remote_task"
      assert output =~ "[on: prod]"
    end
  end

  defp capture_io(device \\ :stdio, fun) do
    ExUnit.CaptureIO.capture_io(device, fun)
  end
end

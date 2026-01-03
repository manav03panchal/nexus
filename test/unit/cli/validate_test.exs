defmodule Nexus.CLI.ValidateTest do
  use ExUnit.Case, async: true
  use Nexus.TestCase

  alias Nexus.CLI.Validate

  @moduletag :unit

  describe "execute/1" do
    setup :tmp_dir

    test "validates a correct configuration", %{tmp_dir: dir} do
      config_content = """
      task :build do
        command "echo building"
      end

      task :test, deps: [:build] do
        command "echo testing"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path},
        flags: %{},
        args: %{}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = Validate.execute(parsed)
        end)

      assert output =~ "Configuration valid"
      assert output =~ "Tasks:  2"
    end

    test "reports file not found", %{tmp_dir: dir} do
      path = Path.join(dir, "nonexistent.exs")

      parsed = %{
        options: %{config: path},
        flags: %{},
        args: %{}
      }

      output =
        capture_io(:stderr, fn ->
          assert {:error, 1} = Validate.execute(parsed)
        end)

      assert output =~ "Config file not found"
    end

    test "reports parse errors", %{tmp_dir: dir} do
      config_content = """
      task :build do
        this_is_invalid_syntax(((
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path},
        flags: %{},
        args: %{}
      }

      output =
        capture_io(:stderr, fn ->
          assert {:error, 1} = Validate.execute(parsed)
        end)

      assert output =~ "Error"
    end

    test "reports circular dependencies", %{tmp_dir: dir} do
      config_content = """
      task :a, deps: [:b] do
        command "echo a"
      end

      task :b, deps: [:a] do
        command "echo b"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path},
        flags: %{},
        args: %{}
      }

      output =
        capture_io(:stderr, fn ->
          assert {:error, 1} = Validate.execute(parsed)
        end)

      assert output =~ "Circular dependency"
    end

    test "reports unknown host references", %{tmp_dir: dir} do
      config_content = """
      task :deploy, on: :unknown_host do
        command "echo deploying"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path},
        flags: %{},
        args: %{}
      }

      output =
        capture_io(:stderr, fn ->
          assert {:error, 1} = Validate.execute(parsed)
        end)

      assert output =~ "Error"
    end

    test "reports unknown dependency references", %{tmp_dir: dir} do
      config_content = """
      task :deploy, deps: [:nonexistent] do
        command "echo deploying"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path},
        flags: %{},
        args: %{}
      }

      output =
        capture_io(:stderr, fn ->
          assert {:error, 1} = Validate.execute(parsed)
        end)

      assert output =~ "Error"
    end

    test "shows summary for valid config with hosts and groups", %{tmp_dir: dir} do
      config_content = """
      host :web1, "web1.example.com"
      host :web2, "web2.example.com"

      group :web, [:web1, :web2]

      task :deploy, on: :web do
        command "echo deploying"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path},
        flags: %{},
        args: %{}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = Validate.execute(parsed)
        end)

      assert output =~ "Tasks:  1"
      assert output =~ "Hosts:  2"
      assert output =~ "Groups: 1"
    end
  end

  defp capture_io(device \\ :stdio, fun) do
    ExUnit.CaptureIO.capture_io(device, fun)
  end
end

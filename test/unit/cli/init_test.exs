defmodule Nexus.CLI.InitTest do
  use ExUnit.Case, async: true
  use Nexus.TestCase

  alias Nexus.CLI.Init

  @moduletag :unit

  describe "execute/1" do
    setup :tmp_dir

    test "creates template file", %{tmp_dir: dir} do
      path = Path.join(dir, "nexus.exs")

      parsed = %{
        options: %{output: path},
        flags: %{force: false},
        args: %{}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = Init.execute(parsed)
        end)

      assert output =~ "Created: #{path}"
      assert output =~ "Next steps"
      assert File.exists?(path)

      content = File.read!(path)
      assert content =~ "# Nexus Configuration"
      assert content =~ "task :build"
      assert content =~ "host"
      assert content =~ "group"
    end

    test "refuses to overwrite existing file without force", %{tmp_dir: dir} do
      path = Path.join(dir, "nexus.exs")
      File.write!(path, "existing content")

      parsed = %{
        options: %{output: path},
        flags: %{force: false},
        args: %{}
      }

      output =
        capture_io(:stderr, fn ->
          assert {:error, 1} = Init.execute(parsed)
        end)

      assert output =~ "File already exists"
      assert output =~ "--force"

      # Original file unchanged
      assert File.read!(path) == "existing content"
    end

    test "overwrites existing file with force flag", %{tmp_dir: dir} do
      path = Path.join(dir, "nexus.exs")
      File.write!(path, "existing content")

      parsed = %{
        options: %{output: path},
        flags: %{force: true},
        args: %{}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = Init.execute(parsed)
        end)

      assert output =~ "Created: #{path}"

      content = File.read!(path)
      assert content =~ "# Nexus Configuration"
      refute content == "existing content"
    end

    test "creates file with custom name", %{tmp_dir: dir} do
      path = Path.join(dir, "custom-config.exs")

      parsed = %{
        options: %{output: path},
        flags: %{force: false},
        args: %{}
      }

      capture_io(fn ->
        assert {:ok, 0} = Init.execute(parsed)
      end)

      assert File.exists?(path)
    end

    test "template includes example tasks" do
      # Get the template content by calling the module
      parsed = %{
        options: %{
          output: Path.join(System.tmp_dir!(), "nexus_init_test_#{:rand.uniform(10000)}.exs")
        },
        flags: %{force: false},
        args: %{}
      }

      capture_io(fn ->
        {:ok, 0} = Init.execute(parsed)
      end)

      content = File.read!(parsed.options.output)
      File.rm(parsed.options.output)

      # Check template has key sections
      assert content =~ "task :build"
      assert content =~ "task :test"
      assert content =~ "deps:"
      assert content =~ "run \""
      assert content =~ "# host"
      assert content =~ "# group"
    end

    test "handles write permission errors gracefully", %{tmp_dir: dir} do
      # Create a read-only directory
      readonly_dir = Path.join(dir, "readonly")
      File.mkdir_p!(readonly_dir)

      path = Path.join(readonly_dir, "nexus.exs")

      # Make directory read-only (Unix only)
      if :os.type() == {:unix, :darwin} or :os.type() == {:unix, :linux} do
        File.chmod!(readonly_dir, 0o444)

        parsed = %{
          options: %{output: path},
          flags: %{force: false},
          args: %{}
        }

        output =
          capture_io(:stderr, fn ->
            assert {:error, 1} = Init.execute(parsed)
          end)

        assert output =~ "Error"

        # Restore permissions for cleanup
        File.chmod!(readonly_dir, 0o755)
      end
    end
  end

  defp capture_io(device \\ :stdio, fun) do
    ExUnit.CaptureIO.capture_io(device, fun)
  end
end

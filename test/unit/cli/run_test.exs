defmodule Nexus.CLI.RunTest do
  use ExUnit.Case, async: true
  use Nexus.TestCase

  alias Nexus.CLI.Run

  @moduletag :unit

  describe "execute/1" do
    setup :tmp_dir

    test "runs a simple local task", %{tmp_dir: dir} do
      config_content = """
      task :build do
        run "echo 'Hello from build'"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, parallel_limit: 10, format: :text},
        flags: %{
          plain: false,
          dry_run: false,
          verbose: false,
          quiet: false,
          continue_on_error: false
        },
        args: %{tasks: "build"}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = Run.execute(parsed)
        end)

      assert output =~ "SUCCESS"
      assert output =~ "1/1 succeeded"
    end

    test "runs dry-run mode", %{tmp_dir: dir} do
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
        options: %{config: path, parallel_limit: 10, format: :text},
        flags: %{
          plain: false,
          dry_run: true,
          verbose: false,
          quiet: false,
          continue_on_error: false
        },
        args: %{tasks: "test"}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = Run.execute(parsed)
        end)

      assert output =~ "Execution Plan"
      assert output =~ "Total tasks: 2"
      assert output =~ "Phase 1: build"
      assert output =~ "Phase 2: test"
    end

    test "shows dry-run with parallel phases", %{tmp_dir: dir} do
      config_content = """
      task :lint do
        run "echo linting"
      end

      task :build do
        run "echo building"
      end

      task :test, deps: [:lint, :build] do
        run "echo testing"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, parallel_limit: 10, format: :text},
        flags: %{
          plain: false,
          dry_run: true,
          verbose: false,
          quiet: false,
          continue_on_error: false
        },
        args: %{tasks: "test"}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = Run.execute(parsed)
        end)

      assert output =~ "parallel"
    end

    test "outputs JSON format for dry-run", %{tmp_dir: dir} do
      config_content = """
      task :build do
        run "echo building"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, parallel_limit: 10, format: :json},
        flags: %{
          plain: false,
          dry_run: true,
          verbose: false,
          quiet: false,
          continue_on_error: false
        },
        args: %{tasks: "build"}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = Run.execute(parsed)
        end)

      # Should contain JSON structure markers
      assert output =~ "total_tasks"
    end

    test "reports config file not found", %{tmp_dir: dir} do
      path = Path.join(dir, "nonexistent.exs")

      parsed = %{
        options: %{config: path, parallel_limit: 10, format: :text},
        flags: %{
          plain: false,
          dry_run: false,
          verbose: false,
          quiet: false,
          continue_on_error: false
        },
        args: %{tasks: "build"}
      }

      output =
        capture_io(:stderr, fn ->
          assert {:error, 1} = Run.execute(parsed)
        end)

      assert output =~ "Config file not found"
    end

    test "reports unknown tasks", %{tmp_dir: dir} do
      config_content = """
      task :build do
        run "echo building"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, parallel_limit: 10, format: :text},
        flags: %{
          plain: false,
          dry_run: false,
          verbose: false,
          quiet: false,
          continue_on_error: false
        },
        args: %{tasks: "unknown_task"}
      }

      output =
        capture_io(:stderr, fn ->
          assert {:error, 1} = Run.execute(parsed)
        end)

      assert output =~ "Unknown tasks"
    end

    test "handles task failure", %{tmp_dir: dir} do
      config_content = """
      task :failing do
        run "exit 1"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, parallel_limit: 10, format: :text},
        flags: %{
          plain: false,
          dry_run: false,
          verbose: false,
          quiet: false,
          continue_on_error: false
        },
        args: %{tasks: "failing"}
      }

      output =
        capture_io(fn ->
          assert {:error, 1} = Run.execute(parsed)
        end)

      assert output =~ "FAILED"
    end

    test "respects quiet mode", %{tmp_dir: dir} do
      config_content = """
      task :build do
        run "echo building"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, parallel_limit: 10, format: :text},
        flags: %{
          plain: false,
          dry_run: false,
          verbose: false,
          quiet: true,
          continue_on_error: false
        },
        args: %{tasks: "build"}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = Run.execute(parsed)
        end)

      # Quiet mode should produce minimal output
      refute output =~ "SUCCESS"
    end

    test "parses comma-separated tasks", %{tmp_dir: dir} do
      config_content = """
      task :lint do
        run "echo linting"
      end

      task :build do
        run "echo building"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, parallel_limit: 10, format: :text},
        flags: %{
          plain: false,
          dry_run: true,
          verbose: false,
          quiet: false,
          continue_on_error: false
        },
        args: %{tasks: "lint,build"}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = Run.execute(parsed)
        end)

      assert output =~ "Total tasks: 2"
    end

    test "parses space-separated tasks", %{tmp_dir: dir} do
      config_content = """
      task :lint do
        run "echo linting"
      end

      task :build do
        run "echo building"
      end
      """

      path = create_nexus_file(dir, config_content)

      parsed = %{
        options: %{config: path, parallel_limit: 10, format: :text},
        flags: %{
          plain: false,
          dry_run: true,
          verbose: false,
          quiet: false,
          continue_on_error: false
        },
        args: %{tasks: "lint build"}
      }

      output =
        capture_io(fn ->
          assert {:ok, 0} = Run.execute(parsed)
        end)

      assert output =~ "Total tasks: 2"
    end
  end

  defp capture_io(device \\ :stdio, fun) do
    ExUnit.CaptureIO.capture_io(device, fun)
  end
end

defmodule Nexus.CLI.PreflightTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Nexus.CLI.Preflight

  setup do
    # Create a temp directory for test config files
    tmp_dir = System.tmp_dir!()
    config_path = Path.join(tmp_dir, "test_preflight_#{:rand.uniform(100_000)}.exs")

    on_exit(fn ->
      File.rm(config_path)
    end)

    {:ok, config_path: config_path}
  end

  describe "execute/1" do
    test "returns success for valid local-only config", %{config_path: config_path} do
      config_content = """
      task :build, on: :local do
        run "echo build"
      end

      task :test, on: :local, deps: [:build] do
        run "echo test"
      end
      """

      File.write!(config_path, config_content)

      parsed = %{
        args: %{tasks: nil},
        options: %{config: config_path, format: :text, skip: nil},
        flags: %{plain: true, verbose: false}
      }

      output =
        capture_io(fn ->
          result = Preflight.execute(parsed)
          assert {:ok, 0} = result
        end)

      assert output =~ "Pre-flight Checks"
      assert output =~ "All checks passed"
    end

    test "returns error for missing config file", %{config_path: config_path} do
      parsed = %{
        args: %{tasks: nil},
        options: %{config: config_path <> "_nonexistent", format: :text, skip: nil},
        flags: %{plain: true, verbose: false}
      }

      output =
        capture_io(fn ->
          result = Preflight.execute(parsed)
          assert {:error, 1} = result
        end)

      assert output =~ "failed"
    end

    test "outputs JSON format when requested", %{config_path: config_path} do
      config_content = """
      task :build, on: :local do
        run "echo build"
      end
      """

      File.write!(config_path, config_content)

      parsed = %{
        args: %{tasks: nil},
        options: %{config: config_path, format: :json, skip: nil},
        flags: %{plain: false, verbose: false}
      }

      output =
        capture_io(fn ->
          result = Preflight.execute(parsed)
          assert {:ok, 0} = result
        end)

      # Should be valid JSON
      assert {:ok, decoded} = Jason.decode(output)
      assert decoded["status"] == "ok"
      assert is_list(decoded["checks"])
      assert is_integer(decoded["duration_ms"])
    end

    test "skips specified checks", %{config_path: config_path} do
      config_content = """
      host :server1, "user@nonexistent.host.local"

      task :deploy, on: :server1 do
        run "echo deploy"
      end
      """

      File.write!(config_path, config_content)

      parsed = %{
        args: %{tasks: nil},
        options: %{config: config_path, format: :text, skip: "hosts,ssh"},
        flags: %{plain: true, verbose: false}
      }

      output =
        capture_io(fn ->
          result = Preflight.execute(parsed)
          assert {:ok, 0} = result
        end)

      assert output =~ "All checks passed"
    end

    test "parses task names from args", %{config_path: config_path} do
      config_content = """
      task :build, on: :local do
        run "echo build"
      end

      task :test, on: :local do
        run "echo test"
      end
      """

      File.write!(config_path, config_content)

      parsed = %{
        args: %{tasks: "build test"},
        options: %{config: config_path, format: :text, skip: nil},
        flags: %{plain: true, verbose: false}
      }

      output =
        capture_io(fn ->
          result = Preflight.execute(parsed)
          assert {:ok, 0} = result
        end)

      assert output =~ "All checks passed"
    end

    test "shows execution plan for valid config", %{config_path: config_path} do
      config_content = """
      task :build, on: :local do
        run "echo build"
      end

      task :test, on: :local, deps: [:build] do
        run "echo test"
      end
      """

      File.write!(config_path, config_content)

      parsed = %{
        args: %{tasks: "test"},
        options: %{config: config_path, format: :text, skip: nil},
        flags: %{plain: true, verbose: false}
      }

      output =
        capture_io(fn ->
          result = Preflight.execute(parsed)
          assert {:ok, 0} = result
        end)

      assert output =~ "Execution Plan"
    end

    test "verbose mode shows details", %{config_path: config_path} do
      config_content = """
      task :build, on: :local do
        run "echo build"
      end
      """

      File.write!(config_path, config_content)

      parsed = %{
        args: %{tasks: nil},
        options: %{config: config_path, format: :text, skip: nil},
        flags: %{plain: true, verbose: true}
      }

      output =
        capture_io(fn ->
          result = Preflight.execute(parsed)
          assert {:ok, 0} = result
        end)

      assert output =~ "Tasks:"
    end

    test "reports unknown tasks", %{config_path: config_path} do
      config_content = """
      task :build, on: :local do
        run "echo build"
      end
      """

      File.write!(config_path, config_content)

      parsed = %{
        args: %{tasks: "nonexistent"},
        options: %{config: config_path, format: :text, skip: nil},
        flags: %{plain: true, verbose: false}
      }

      output =
        capture_io(fn ->
          result = Preflight.execute(parsed)
          assert {:error, 1} = result
        end)

      assert output =~ "Unknown tasks"
    end
  end

  describe "parse_tasks/1" do
    test "handles nil" do
      parsed = %{
        args: %{tasks: nil},
        options: %{config: "fake.exs", format: :text, skip: nil},
        flags: %{plain: true, verbose: false}
      }

      # We can't directly test private functions, but we test through execute
      # with nil tasks which exercises parse_tasks(nil)
      capture_io(fn ->
        # This will fail on config but exercises the parse_tasks path
        Preflight.execute(parsed)
      end)
    end

    test "handles empty string" do
      parsed = %{
        args: %{tasks: ""},
        options: %{config: "fake.exs", format: :text, skip: nil},
        flags: %{plain: true, verbose: false}
      }

      capture_io(fn ->
        Preflight.execute(parsed)
      end)
    end
  end

  describe "parse_skip_checks/1" do
    test "handles nil skip option", %{config_path: config_path} do
      config_content = """
      task :build, on: :local do
        run "echo build"
      end
      """

      File.write!(config_path, config_content)

      parsed = %{
        args: %{tasks: nil},
        options: %{config: config_path, format: :text, skip: nil},
        flags: %{plain: true, verbose: false}
      }

      capture_io(fn ->
        result = Preflight.execute(parsed)
        assert {:ok, 0} = result
      end)
    end

    test "parses comma-separated skip list", %{config_path: config_path} do
      config_content = """
      host :server1, "user@nonexistent.local"
      task :deploy, on: :server1 do
        run "echo deploy"
      end
      """

      File.write!(config_path, config_content)

      parsed = %{
        args: %{tasks: nil},
        options: %{config: config_path, format: :text, skip: "hosts, ssh"},
        flags: %{plain: true, verbose: false}
      }

      output =
        capture_io(fn ->
          result = Preflight.execute(parsed)
          assert {:ok, 0} = result
        end)

      assert output =~ "All checks passed"
    end
  end
end

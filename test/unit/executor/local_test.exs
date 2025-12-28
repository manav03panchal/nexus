defmodule Nexus.Executor.LocalTest do
  use ExUnit.Case, async: true

  alias Nexus.Executor.Local
  alias Nexus.Types.Command

  @moduletag :unit

  describe "run/2" do
    test "executes simple command and captures output" do
      assert {:ok, output, 0} = Local.run("echo hello")
      assert String.trim(output) == "hello"
    end

    test "captures multi-line output" do
      assert {:ok, output, 0} = Local.run("printf 'line1\nline2\nline3'")
      lines = String.split(output, "\n", trim: true)
      assert length(lines) == 3
    end

    test "returns non-zero exit code on failure" do
      assert {:ok, _output, 42} = Local.run("exit 42")
    end

    test "returns exit code 1 for false command" do
      assert {:ok, _output, 1} = Local.run("false")
    end

    test "returns exit code 0 for true command" do
      assert {:ok, _output, 0} = Local.run("true")
    end

    test "captures stderr merged with stdout" do
      assert {:ok, output, _} = Local.run("echo error >&2")
      assert String.contains?(output, "error")
    end

    test "handles command with arguments" do
      assert {:ok, output, 0} = Local.run("echo one two three")
      assert String.trim(output) == "one two three"
    end

    test "handles command with single quotes" do
      assert {:ok, output, 0} = Local.run("echo 'hello world'")
      assert String.trim(output) == "hello world"
    end

    test "handles command with double quotes" do
      assert {:ok, output, 0} = Local.run("echo \"quoted string\"")
      assert String.trim(output) == "quoted string"
    end

    test "handles command with pipes" do
      assert {:ok, output, 0} = Local.run("echo hello | tr 'a-z' 'A-Z'")
      assert String.trim(output) == "HELLO"
    end

    test "handles shell variable expansion" do
      assert {:ok, output, 0} = Local.run("echo $HOME")
      assert String.trim(output) != ""
      assert String.trim(output) != "$HOME"
    end

    test "respects working directory option" do
      assert {:ok, output, 0} = Local.run("pwd", cd: "/tmp")
      assert String.contains?(output, "tmp")
    end

    test "passes environment variables" do
      assert {:ok, output, 0} = Local.run("echo $TEST_VAR", env: [{"TEST_VAR", "test_value"}])
      assert String.trim(output) == "test_value"
    end

    test "passes multiple environment variables" do
      env = [{"VAR1", "value1"}, {"VAR2", "value2"}]
      assert {:ok, output, 0} = Local.run("echo $VAR1 $VAR2", env: env)
      assert String.trim(output) == "value1 value2"
    end

    test "timeout returns error" do
      assert {:error, :timeout} = Local.run("sleep 10", timeout: 100)
    end

    test "command completes before timeout" do
      assert {:ok, output, 0} = Local.run("echo fast", timeout: 5000)
      assert String.trim(output) == "fast"
    end

    test "handles empty output" do
      assert {:ok, "", 0} = Local.run("true")
    end

    test "accepts Command struct" do
      command = %Command{cmd: "echo from struct", timeout: 5000}
      assert {:ok, output, 0} = Local.run(command)
      assert String.trim(output) == "from struct"
    end

    test "Command struct timeout is respected" do
      command = %Command{cmd: "sleep 10", timeout: 100}
      assert {:error, :timeout} = Local.run(command)
    end

    test "handles command not found" do
      assert {:ok, output, exit_code} = Local.run("nonexistent_command_xyz_123")
      assert exit_code != 0
      assert String.contains?(output, "not found")
    end

    test "handles large output" do
      assert {:ok, output, 0} = Local.run("seq 1 1000")
      lines = String.split(String.trim(output), "\n")
      assert length(lines) == 1000
    end
  end

  describe "run_streaming/3" do
    test "streams output to callback" do
      parent = self()
      ref = make_ref()

      callback = fn chunk -> send(parent, {ref, chunk}) end

      Task.start(fn ->
        Local.run_streaming("echo line1; echo line2", [], callback)
      end)

      chunks = collect_stream_chunks(ref, 2000)

      stdout_chunks = for {:stdout, data} <- chunks, do: data
      combined = Enum.join(stdout_chunks)

      assert String.contains?(combined, "line1")
      assert String.contains?(combined, "line2")
    end

    test "callback receives exit code" do
      parent = self()
      ref = make_ref()

      callback = fn chunk -> send(parent, {ref, chunk}) end

      Task.start(fn ->
        Local.run_streaming("exit 5", [], callback)
      end)

      chunks = collect_stream_chunks(ref, 2000)

      assert Enum.any?(chunks, &match?({:exit, 5}, &1))
    end

    test "streaming respects timeout" do
      callback = fn _chunk -> :ok end
      assert {:error, :timeout} = Local.run_streaming("sleep 10", [timeout: 100], callback)
    end

    test "accepts Command struct" do
      parent = self()
      ref = make_ref()

      callback = fn chunk -> send(parent, {ref, chunk}) end

      command = %Command{cmd: "echo streaming", timeout: 5000}

      Task.start(fn ->
        Local.run_streaming(command, [], callback)
      end)

      chunks = collect_stream_chunks(ref, 2000)
      stdout_chunks = for {:stdout, data} <- chunks, do: data
      combined = Enum.join(stdout_chunks)

      assert String.contains?(combined, "streaming")
    end
  end

  describe "run_sudo/2" do
    @describetag :skip

    test "builds sudo command without user" do
      # Skipped - requires sudo access
      assert {:ok, _output, _code} = Local.run_sudo("whoami")
    end

    test "builds sudo command with user" do
      # Skipped - requires sudo access
      assert {:ok, _output, _code} = Local.run_sudo("whoami", user: "nobody")
    end
  end

  # Helpers

  defp collect_stream_chunks(ref, timeout) do
    collect_stream_chunks(ref, timeout, [])
  end

  defp collect_stream_chunks(ref, timeout, acc) do
    receive do
      {^ref, chunk} ->
        collect_stream_chunks(ref, timeout, [chunk | acc])
    after
      timeout ->
        Enum.reverse(acc)
    end
  end
end

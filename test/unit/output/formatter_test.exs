defmodule Nexus.Output.FormatterTest do
  use ExUnit.Case, async: true

  alias Nexus.Output.Formatter
  alias Nexus.Types.Command
  alias Nexus.Types.Task, as: NexusTask

  describe "format_task_start/2" do
    setup do
      task = %NexusTask{
        name: :deploy,
        on: :web_servers,
        deps: [:build],
        commands: [
          %Command{cmd: "echo deploy", sudo: false, user: nil, timeout: 5000}
        ],
        timeout: 30_000,
        strategy: :parallel
      }

      local_task = %NexusTask{
        name: :build,
        on: :local,
        deps: [],
        commands: [%Command{cmd: "mix compile", sudo: false, user: nil, timeout: 5000}],
        timeout: 60_000,
        strategy: :serial
      }

      {:ok, task: task, local_task: local_task}
    end

    test "formats task start in text format", %{task: task} do
      result = Formatter.format_task_start(task, format: :text)
      assert result == "Running task: deploy [web_servers]"
    end

    test "formats local task start in text format", %{local_task: task} do
      result = Formatter.format_task_start(task, format: :text)
      assert result == "Running task: build [local]"
    end

    test "returns empty string in quiet mode", %{task: task} do
      result = Formatter.format_task_start(task, format: :text, verbosity: :quiet)
      assert result == ""
    end

    test "formats task start in JSON format", %{task: task} do
      result = Formatter.format_task_start(task, format: :json)
      decoded = Jason.decode!(result)

      assert decoded["event"] == "task_start"
      assert decoded["task"] == "deploy"
      assert decoded["on"] == "web_servers"
      assert decoded["commands"] == 1
    end

    test "JSON format ignores verbosity", %{task: task} do
      result = Formatter.format_task_start(task, format: :json, verbosity: :quiet)
      decoded = Jason.decode!(result)
      assert decoded["event"] == "task_start"
    end
  end

  describe "format_task_complete/3" do
    setup do
      task = %NexusTask{
        name: :deploy,
        on: :web_servers,
        deps: [],
        commands: [],
        timeout: 30_000,
        strategy: :parallel
      }

      success_result = %{status: :ok, duration_ms: 1234}
      error_result = %{status: :error, duration_ms: 567}

      {:ok, task: task, success: success_result, error: error_result}
    end

    test "formats successful task completion", %{task: task, success: result} do
      output = Formatter.format_task_complete(task, result, format: :text)
      assert output =~ "[ok]"
      assert output =~ "deploy"
      assert output =~ "1.2s"
    end

    test "formats failed task completion", %{task: task, error: result} do
      output = Formatter.format_task_complete(task, result, format: :text)
      assert output =~ "[FAILED]"
      assert output =~ "deploy"
      assert output =~ "567ms"
    end

    test "returns empty string in quiet mode", %{task: task, success: result} do
      output = Formatter.format_task_complete(task, result, format: :text, verbosity: :quiet)
      assert output == ""
    end

    test "formats task completion in JSON", %{task: task, success: result} do
      output = Formatter.format_task_complete(task, result, format: :json)
      decoded = Jason.decode!(output)

      assert decoded["event"] == "task_complete"
      assert decoded["task"] == "deploy"
      assert decoded["status"] == "ok"
      assert decoded["duration_ms"] == 1234
    end

    test "formats duration in minutes for long tasks", %{task: task} do
      result = %{status: :ok, duration_ms: 125_000}
      output = Formatter.format_task_complete(task, result, format: :text)
      assert output =~ "2m"
    end
  end

  describe "format_command_start/2" do
    test "returns empty string in normal mode" do
      result = Formatter.format_command_start("echo hello", format: :text, verbosity: :normal)
      assert result == ""
    end

    test "formats command in verbose mode" do
      result = Formatter.format_command_start("echo hello", format: :text, verbosity: :verbose)
      assert result == "    $ echo hello"
    end

    test "truncates long commands in verbose mode" do
      long_cmd = String.duplicate("x", 100)
      result = Formatter.format_command_start(long_cmd, format: :text, verbosity: :verbose)
      assert result =~ "..."
      assert String.length(result) < 80
    end

    test "formats command in JSON" do
      result = Formatter.format_command_start("echo hello", format: :json)
      decoded = Jason.decode!(result)

      assert decoded["event"] == "command_start"
      assert decoded["command"] == "echo hello"
    end
  end

  describe "format_command_complete/3" do
    test "returns empty string in normal mode" do
      result =
        Formatter.format_command_complete("echo hello", 0, format: :text, verbosity: :normal)

      assert result == ""
    end

    test "formats success in verbose mode" do
      result =
        Formatter.format_command_complete("echo hello", 0, format: :text, verbosity: :verbose)

      assert result == "    [ok]"
    end

    test "formats failure in verbose mode" do
      result =
        Formatter.format_command_complete("echo hello", 1, format: :text, verbosity: :verbose)

      assert result == "    [exit 1]"
    end

    test "formats completion in JSON" do
      result = Formatter.format_command_complete("echo hello", 0, format: :json)
      decoded = Jason.decode!(result)

      assert decoded["event"] == "command_complete"
      assert decoded["command"] == "echo hello"
      assert decoded["exit_code"] == 0
    end
  end

  describe "format_error/2" do
    test "formats file not found error" do
      result = Formatter.format_error({:file_not_found, "/path/to/file"}, format: :text)
      assert result == "Error: File not found: /path/to/file"
    end

    test "formats unknown tasks error" do
      result = Formatter.format_error({:unknown_tasks, [:foo, :bar]}, format: :text)
      assert result == "Error: Unknown tasks: foo, bar"
    end

    test "formats cycle error" do
      result = Formatter.format_error({:cycle, [:a, :b, :c, :a]}, format: :text)
      assert result == "Error: Circular dependency: a -> b -> c -> a"
    end

    test "formats connection failed error" do
      result = Formatter.format_error({:connection_failed, "server.example.com"}, format: :text)
      assert result == "Error: Connection failed: server.example.com"
    end

    test "formats auth failed error" do
      result = Formatter.format_error({:auth_failed, "server.example.com"}, format: :text)
      assert result == "Error: Authentication failed: server.example.com"
    end

    test "formats timeout error" do
      result = Formatter.format_error({:timeout, "slow_command"}, format: :text)
      assert result == "Error: Command timed out: slow_command"
    end

    test "formats string error" do
      result = Formatter.format_error("Something went wrong", format: :text)
      assert result == "Error: Something went wrong"
    end

    test "formats generic error" do
      result = Formatter.format_error({:unexpected, "data"}, format: :text)
      assert result =~ "Error:"
      assert result =~ "unexpected"
    end

    test "formats error in JSON" do
      result = Formatter.format_error({:file_not_found, "/path"}, format: :json)
      decoded = Jason.decode!(result)

      assert decoded["event"] == "error"
      assert decoded["message"] =~ "File not found"
    end
  end

  describe "format_pipeline_result/2" do
    setup do
      success_result = %{
        status: :ok,
        duration_ms: 5000,
        tasks_run: 3,
        tasks_succeeded: 3,
        tasks_failed: 0,
        aborted_at: nil
      }

      failed_result = %{
        status: :error,
        duration_ms: 2500,
        tasks_run: 3,
        tasks_succeeded: 1,
        tasks_failed: 2,
        aborted_at: :test
      }

      {:ok, success: success_result, failed: failed_result}
    end

    test "formats successful pipeline in text", %{success: result} do
      output = Formatter.format_pipeline_result(result, format: :text)

      assert output =~ "SUCCESS"
      assert output =~ "5.0s"
      assert output =~ "3/3 succeeded"
      refute output =~ "Aborted"
    end

    test "formats failed pipeline in text", %{failed: result} do
      output = Formatter.format_pipeline_result(result, format: :text)

      assert output =~ "FAILED"
      assert output =~ "2.5s"
      assert output =~ "1/3 succeeded"
      assert output =~ "Aborted at: test"
    end

    test "formats pipeline in quiet mode", %{success: result} do
      output = Formatter.format_pipeline_result(result, format: :text, verbosity: :quiet)
      assert output == "OK"
    end

    test "formats failed pipeline in quiet mode", %{failed: result} do
      output = Formatter.format_pipeline_result(result, format: :text, verbosity: :quiet)
      assert output == "FAILED"
    end

    test "formats pipeline in JSON", %{success: result} do
      output = Formatter.format_pipeline_result(result, format: :json)
      decoded = Jason.decode!(output)

      assert decoded["event"] == "pipeline_complete"
      assert decoded["status"] == "ok"
      assert decoded["duration_ms"] == 5000
      assert decoded["tasks_run"] == 3
      assert decoded["tasks_succeeded"] == 3
      assert decoded["tasks_failed"] == 0
      assert decoded["aborted_at"] == nil
    end

    test "formats aborted pipeline in JSON", %{failed: result} do
      output = Formatter.format_pipeline_result(result, format: :json)
      decoded = Jason.decode!(output)

      assert decoded["aborted_at"] == "test"
    end
  end

  describe "format_output/2" do
    test "returns empty string in normal mode" do
      result = Formatter.format_output("hello\nworld", format: :text, verbosity: :normal)
      assert result == ""
    end

    test "prefixes lines in verbose mode" do
      result = Formatter.format_output("hello\nworld", format: :text, verbosity: :verbose)
      assert result == "      | hello\n      | world"
    end

    test "formats output in JSON" do
      result = Formatter.format_output("hello\nworld", format: :json)
      decoded = Jason.decode!(result)

      assert decoded["event"] == "output"
      assert decoded["content"] == "hello\nworld"
    end
  end

  describe "format_host_connect/2" do
    test "returns empty string in normal mode" do
      result = Formatter.format_host_connect(:web1, format: :text, verbosity: :normal)
      assert result == ""
    end

    test "formats connection in verbose mode" do
      result = Formatter.format_host_connect(:web1, format: :text, verbosity: :verbose)
      assert result == "  Connecting to web1..."
    end

    test "handles string host" do
      result =
        Formatter.format_host_connect("server.example.com", format: :text, verbosity: :verbose)

      assert result == "  Connecting to server.example.com..."
    end

    test "formats connection in JSON" do
      result = Formatter.format_host_connect(:web1, format: :json)
      decoded = Jason.decode!(result)

      assert decoded["event"] == "host_connect"
      assert decoded["host"] == "web1"
    end
  end

  describe "format_retry/4" do
    test "formats retry in text" do
      result = Formatter.format_retry("failing_command", 2, 3, format: :text)
      assert result == "    Retry 2/3: failing_command"
    end

    test "truncates long command in retry" do
      long_cmd = String.duplicate("x", 100)
      result = Formatter.format_retry(long_cmd, 1, 3, format: :text)
      assert result =~ "..."
    end

    test "formats retry in JSON" do
      result = Formatter.format_retry("failing_command", 2, 3, format: :json)
      decoded = Jason.decode!(result)

      assert decoded["event"] == "retry"
      assert decoded["command"] == "failing_command"
      assert decoded["attempt"] == 2
      assert decoded["max_attempts"] == 3
    end
  end
end

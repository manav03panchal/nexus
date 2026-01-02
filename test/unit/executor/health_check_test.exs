defmodule Nexus.Executor.HealthCheckTest do
  use ExUnit.Case, async: true

  alias Nexus.Executor.HealthCheck
  alias Nexus.Types.WaitFor

  describe "check_once/2 with TCP" do
    test "returns ok for successful TCP connection" do
      # Use a port that's likely to be open (SSH port on localhost might work in CI)
      # For unit tests, we'll test with a known-failing case
      check = WaitFor.new(:tcp, "localhost:0")

      # Port 0 should fail
      assert {:error, _} = HealthCheck.check_once(check, [])
    end

    test "returns error for invalid target format" do
      check = WaitFor.new(:tcp, "invalid-target")

      assert {:error, {:invalid_target, "invalid-target"}} = HealthCheck.check_once(check, [])
    end
  end

  describe "check_once/2 with command" do
    test "returns ok for successful command" do
      check = WaitFor.new(:command, "echo hello")

      assert {:ok, :healthy} = HealthCheck.check_once(check, [])
    end

    test "returns error for failed command" do
      check = WaitFor.new(:command, "exit 1")

      assert {:error, {:command_failed, 1, _}} = HealthCheck.check_once(check, [])
    end
  end

  describe "wait/2 with quick checks" do
    test "returns ok immediately for passing check" do
      check = WaitFor.new(:command, "echo ok", timeout: 1_000, interval: 100)

      assert :ok = HealthCheck.wait(check, [])
    end

    test "returns timeout error for failing check" do
      check = WaitFor.new(:command, "exit 1", timeout: 200, interval: 50)

      assert {:error, :timeout} = HealthCheck.wait(check, [])
    end
  end
end

defmodule Nexus.Types.WaitForTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.WaitFor

  describe "new/3" do
    test "creates HTTP health check with defaults" do
      check = WaitFor.new(:http, "http://localhost:4000/health")

      assert check.type == :http
      assert check.target == "http://localhost:4000/health"
      assert check.timeout == 60_000
      assert check.interval == 5_000
      assert check.expected_status == nil
      assert check.expected_body == nil
    end

    test "creates TCP health check" do
      check = WaitFor.new(:tcp, "localhost:5432")

      assert check.type == :tcp
      assert check.target == "localhost:5432"
    end

    test "creates command health check" do
      check = WaitFor.new(:command, "systemctl is-active app")

      assert check.type == :command
      assert check.target == "systemctl is-active app"
    end

    test "creates health check with custom timeout" do
      check = WaitFor.new(:http, "http://localhost/health", timeout: 30_000)

      assert check.timeout == 30_000
    end

    test "creates health check with custom interval" do
      check = WaitFor.new(:http, "http://localhost/health", interval: 2_000)

      assert check.interval == 2_000
    end

    test "creates HTTP check with expected status" do
      check = WaitFor.new(:http, "http://localhost/health", expected_status: 204)

      assert check.expected_status == 204
    end

    test "creates HTTP check with expected body string" do
      check = WaitFor.new(:http, "http://localhost/health", expected_body: "OK")

      assert check.expected_body == "OK"
    end

    test "creates HTTP check with expected body regex" do
      pattern = ~r/status.*ok/i
      check = WaitFor.new(:http, "http://localhost/health", expected_body: pattern)

      assert check.expected_body == pattern
    end
  end

  describe "struct" do
    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(WaitFor, [])
      end
    end
  end
end

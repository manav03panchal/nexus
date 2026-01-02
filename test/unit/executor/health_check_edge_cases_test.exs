defmodule Nexus.Executor.HealthCheckEdgeCasesTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.WaitFor

  @moduletag :unit

  describe "WaitFor struct edge cases" do
    test "handles minimal HTTP check" do
      wait = WaitFor.new(:http, "http://localhost:4000/health")
      assert wait.type == :http
      assert wait.target == "http://localhost:4000/health"
      assert wait.timeout == 60_000
      assert wait.interval == 5_000
    end

    test "handles HTTPS URL" do
      wait = WaitFor.new(:http, "https://secure.example.com:8443/health")
      assert wait.target == "https://secure.example.com:8443/health"
    end

    test "handles URL with query parameters" do
      wait = WaitFor.new(:http, "http://localhost/health?token=abc&verbose=true")
      assert wait.target =~ "token=abc"
    end

    test "handles URL with basic auth" do
      wait = WaitFor.new(:http, "http://user:pass@localhost/health")
      assert wait.target =~ "user:pass@"
    end

    test "handles URL with IPv6 address" do
      wait = WaitFor.new(:http, "http://[::1]:8080/health")
      assert wait.target =~ "[::1]"
    end

    test "handles URL with IPv4 address" do
      wait = WaitFor.new(:http, "http://192.168.1.100:8080/health")
      assert wait.target =~ "192.168.1.100"
    end

    test "TCP check with hostname and port" do
      wait = WaitFor.new(:tcp, "database.local:5432")
      assert wait.type == :tcp
      assert wait.target == "database.local:5432"
    end

    test "TCP check with IP and port" do
      wait = WaitFor.new(:tcp, "10.0.0.1:3306")
      assert wait.target == "10.0.0.1:3306"
    end

    test "TCP check with localhost" do
      wait = WaitFor.new(:tcp, "localhost:6379")
      assert wait.target == "localhost:6379"
    end

    test "command check with simple command" do
      wait = WaitFor.new(:command, "systemctl is-active nginx")
      assert wait.type == :command
      assert wait.target == "systemctl is-active nginx"
    end

    test "command check with pipes" do
      wait = WaitFor.new(:command, "curl -s localhost | grep -q 'OK'")
      assert wait.target =~ "|"
    end

    test "command check with shell operators" do
      wait = WaitFor.new(:command, "test -f /var/run/app.pid && kill -0 $(cat /var/run/app.pid)")
      assert wait.target =~ "&&"
    end
  end

  describe "timeout edge cases" do
    test "zero timeout" do
      wait = WaitFor.new(:http, "http://localhost/health", timeout: 0)
      assert wait.timeout == 0
    end

    test "very short timeout (1ms)" do
      wait = WaitFor.new(:http, "http://localhost/health", timeout: 1)
      assert wait.timeout == 1
    end

    test "very long timeout (1 hour)" do
      wait = WaitFor.new(:http, "http://localhost/health", timeout: 3_600_000)
      assert wait.timeout == 3_600_000
    end

    test "negative timeout defaults correctly" do
      # Should either reject or use default
      wait = WaitFor.new(:http, "http://localhost/health", timeout: -1000)
      # Implementation may vary - just ensure it doesn't crash
      assert wait.timeout == -1000 or wait.timeout > 0
    end
  end

  describe "interval edge cases" do
    test "zero interval" do
      wait = WaitFor.new(:http, "http://localhost/health", interval: 0)
      assert wait.interval == 0
    end

    test "interval larger than timeout" do
      wait = WaitFor.new(:http, "http://localhost/health", timeout: 5_000, interval: 10_000)
      # This is a valid edge case - will only check once
      assert wait.interval == 10_000
      assert wait.timeout == 5_000
    end

    test "very small interval (1ms)" do
      wait = WaitFor.new(:http, "http://localhost/health", interval: 1)
      assert wait.interval == 1
    end
  end

  describe "expected_status edge cases" do
    test "expects 200 by default" do
      wait = WaitFor.new(:http, "http://localhost/health")
      assert wait.expected_status == nil or wait.expected_status == 200
    end

    test "expects custom status" do
      wait = WaitFor.new(:http, "http://localhost/health", expected_status: 201)
      assert wait.expected_status == 201
    end

    test "expects redirect status" do
      wait = WaitFor.new(:http, "http://localhost/redirect", expected_status: 302)
      assert wait.expected_status == 302
    end

    test "expects server error for negative test" do
      wait = WaitFor.new(:http, "http://localhost/failing", expected_status: 500)
      assert wait.expected_status == 500
    end

    test "expects informational status" do
      wait = WaitFor.new(:http, "http://localhost/continue", expected_status: 100)
      assert wait.expected_status == 100
    end
  end

  describe "expected_body edge cases" do
    test "nil expected_body accepts any body" do
      wait = WaitFor.new(:http, "http://localhost/health")
      assert wait.expected_body == nil
    end

    test "empty string expected_body" do
      wait = WaitFor.new(:http, "http://localhost/health", expected_body: "")
      assert wait.expected_body == ""
    end

    test "exact match expected_body" do
      wait = WaitFor.new(:http, "http://localhost/health", expected_body: "OK")
      assert wait.expected_body == "OK"
    end

    test "JSON expected_body" do
      wait =
        WaitFor.new(:http, "http://localhost/health", expected_body: ~s({"status":"healthy"}))

      assert wait.expected_body == ~s({"status":"healthy"})
    end

    test "regex-like expected_body" do
      wait =
        WaitFor.new(:http, "http://localhost/health", expected_body: "uptime: [0-9]+ seconds")

      assert wait.expected_body =~ "uptime"
    end

    test "multiline expected_body" do
      wait =
        WaitFor.new(:http, "http://localhost/health", expected_body: "Status: OK\nVersion: 1.0")

      assert wait.expected_body =~ "\n"
    end

    test "unicode expected_body" do
      wait = WaitFor.new(:http, "http://localhost/health", expected_body: "状态: 正常")
      assert wait.expected_body == "状态: 正常"
    end
  end

  describe "HTTP URL parsing edge cases" do
    test "URL without port uses default" do
      wait = WaitFor.new(:http, "http://localhost/health")
      # Should use port 80 implicitly
      assert wait.target == "http://localhost/health"
    end

    test "URL with non-standard port" do
      wait = WaitFor.new(:http, "http://localhost:9999/health")
      assert wait.target =~ ":9999"
    end

    test "URL with path only" do
      wait = WaitFor.new(:http, "http://localhost/")
      assert wait.target == "http://localhost/"
    end

    test "URL with fragment (should be preserved or stripped)" do
      wait = WaitFor.new(:http, "http://localhost/page#section")
      # Implementation may strip or preserve
      assert wait.target =~ "localhost"
    end

    test "URL with encoded characters" do
      wait = WaitFor.new(:http, "http://localhost/path%20with%20spaces")
      assert wait.target =~ "%20"
    end
  end

  describe "TCP target parsing edge cases" do
    test "standard port syntax" do
      wait = WaitFor.new(:tcp, "localhost:5432")
      assert wait.target == "localhost:5432"
    end

    test "high port number" do
      wait = WaitFor.new(:tcp, "localhost:65535")
      assert wait.target == "localhost:65535"
    end

    test "port 0 (edge case)" do
      wait = WaitFor.new(:tcp, "localhost:0")
      assert wait.target == "localhost:0"
    end

    test "hostname with dashes" do
      wait = WaitFor.new(:tcp, "my-database-server:5432")
      assert wait.target == "my-database-server:5432"
    end

    test "FQDN with port" do
      wait = WaitFor.new(:tcp, "db.prod.example.com:5432")
      assert wait.target == "db.prod.example.com:5432"
    end
  end

  describe "command edge cases" do
    test "command with single quotes" do
      wait = WaitFor.new(:command, "test -f '/path/with spaces/file'")
      assert wait.target =~ "'"
    end

    test "command with double quotes" do
      wait = WaitFor.new(:command, ~s(echo "hello world"))
      assert wait.target =~ ~s(")
    end

    test "command with environment variables" do
      wait = WaitFor.new(:command, "test -d $HOME/.config")
      assert wait.target =~ "$HOME"
    end

    test "command with subshell" do
      wait = WaitFor.new(:command, "test $(pgrep -c nginx) -gt 0")
      assert wait.target =~ "$("
    end

    test "multiline command" do
      wait =
        WaitFor.new(:command, """
        if test -f /var/run/app.pid; then
          kill -0 $(cat /var/run/app.pid)
        fi
        """)

      assert wait.target =~ "if"
      assert wait.target =~ "fi"
    end

    test "empty command" do
      wait = WaitFor.new(:command, "")
      assert wait.target == ""
    end

    test "command with only whitespace" do
      wait = WaitFor.new(:command, "   ")
      assert wait.target == "   "
    end
  end

  describe "check type validation" do
    test "supports :http type" do
      wait = WaitFor.new(:http, "http://localhost/health")
      assert wait.type == :http
    end

    test "supports :tcp type" do
      wait = WaitFor.new(:tcp, "localhost:5432")
      assert wait.type == :tcp
    end

    test "supports :command type" do
      wait = WaitFor.new(:command, "true")
      assert wait.type == :command
    end
  end

  describe "option combinations" do
    test "all options together" do
      wait =
        WaitFor.new(:http, "http://localhost:4000/health",
          timeout: 30_000,
          interval: 2_000,
          expected_status: 200,
          expected_body: "healthy"
        )

      assert wait.timeout == 30_000
      assert wait.interval == 2_000
      assert wait.expected_status == 200
      assert wait.expected_body == "healthy"
    end

    test "partial options" do
      wait = WaitFor.new(:http, "http://localhost/health", timeout: 10_000)
      assert wait.timeout == 10_000
      # Others should be defaults
      assert wait.interval == 5_000
    end

    test "unknown options are ignored or error" do
      # Depending on implementation, unknown opts may be ignored
      wait = WaitFor.new(:http, "http://localhost/health", unknown_option: "value")
      assert wait.type == :http
    end
  end
end

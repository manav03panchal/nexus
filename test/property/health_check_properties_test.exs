defmodule Nexus.Property.HealthCheckPropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Nexus.Types.WaitFor

  @moduletag :property

  describe "WaitFor struct properties" do
    property "type is preserved for http" do
      check all(url <- string(:alphanumeric, min_length: 1)) do
        wait = WaitFor.new(:http, "http://localhost/#{url}")
        assert wait.type == :http
      end
    end

    property "type is preserved for tcp" do
      check all(port <- integer(1..65_535)) do
        wait = WaitFor.new(:tcp, "localhost:#{port}")
        assert wait.type == :tcp
      end
    end

    property "type is preserved for command" do
      check all(cmd <- string(:alphanumeric, min_length: 1)) do
        wait = WaitFor.new(:command, cmd)
        assert wait.type == :command
      end
    end

    property "target is preserved" do
      check all(target <- string(:printable, min_length: 1, max_length: 200)) do
        wait = WaitFor.new(:http, target)
        assert wait.target == target
      end
    end

    property "timeout option is preserved" do
      check all(timeout <- positive_integer()) do
        wait = WaitFor.new(:http, "http://localhost/health", timeout: timeout)
        assert wait.timeout == timeout
      end
    end

    property "interval option is preserved" do
      check all(interval <- positive_integer()) do
        wait = WaitFor.new(:http, "http://localhost/health", interval: interval)
        assert wait.interval == interval
      end
    end

    property "expected_status is preserved for http" do
      check all(status <- integer(100..599)) do
        wait = WaitFor.new(:http, "http://localhost/health", expected_status: status)
        assert wait.expected_status == status
      end
    end

    property "expected_body is preserved" do
      check all(body <- string(:printable, max_length: 100)) do
        wait = WaitFor.new(:http, "http://localhost/health", expected_body: body)
        assert wait.expected_body == body
      end
    end
  end

  describe "WaitFor defaults" do
    property "default timeout is 60_000" do
      check all(target <- string(:alphanumeric, min_length: 1)) do
        wait = WaitFor.new(:http, "http://#{target}")
        assert wait.timeout == 60_000
      end
    end

    property "default interval is 5_000" do
      check all(target <- string(:alphanumeric, min_length: 1)) do
        wait = WaitFor.new(:http, "http://#{target}")
        assert wait.interval == 5_000
      end
    end
  end

  describe "TCP target format" do
    property "tcp targets have host:port format" do
      check all(
              host <- string(:alphanumeric, min_length: 1, max_length: 50),
              port <- integer(1..65_535)
            ) do
        target = "#{host}:#{port}"
        wait = WaitFor.new(:tcp, target)
        assert wait.target == target
        assert String.contains?(wait.target, ":")
      end
    end
  end

  describe "HTTP URL properties" do
    property "http targets start with http" do
      check all(path <- string(:alphanumeric, min_length: 1)) do
        target = "http://localhost/#{path}"
        wait = WaitFor.new(:http, target)
        assert String.starts_with?(wait.target, "http")
      end
    end

    property "https targets are valid" do
      check all(path <- string(:alphanumeric, min_length: 1)) do
        target = "https://localhost/#{path}"
        wait = WaitFor.new(:http, target)
        assert String.starts_with?(wait.target, "https")
      end
    end
  end

  describe "command check properties" do
    property "command targets are preserved exactly" do
      check all(cmd <- string(:printable, min_length: 1, max_length: 200)) do
        wait = WaitFor.new(:command, cmd)
        assert wait.target == cmd
      end
    end

    property "complex shell commands are preserved" do
      check all(
              cmd1 <- string(:alphanumeric, min_length: 1),
              cmd2 <- string(:alphanumeric, min_length: 1)
            ) do
        complex = "#{cmd1} && #{cmd2}"
        wait = WaitFor.new(:command, complex)
        assert wait.target == complex
      end
    end
  end

  describe "option combinations" do
    property "all options can be set together" do
      check all(
              timeout <- positive_integer(),
              interval <- positive_integer(),
              status <- integer(100..599),
              body <- string(:alphanumeric, max_length: 50)
            ) do
        wait =
          WaitFor.new(:http, "http://localhost/health",
            timeout: timeout,
            interval: interval,
            expected_status: status,
            expected_body: body
          )

        assert wait.timeout == timeout
        assert wait.interval == interval
        assert wait.expected_status == status
        assert wait.expected_body == body
      end
    end
  end
end

defmodule Nexus.Resources.DiffFormatterTest do
  use ExUnit.Case, async: true

  alias Nexus.Resources.DiffFormatter
  alias Nexus.Resources.Result

  describe "format/2" do
    test "formats ok result" do
      result = Result.ok("package[nginx]")
      formatted = DiffFormatter.format(result)

      assert formatted =~ "package[nginx]"
      assert formatted =~ "ok"
    end

    test "formats changed result" do
      diff = %{changes: ["installed"]}
      result = Result.changed("package[nginx]", diff)
      formatted = DiffFormatter.format(result)

      assert formatted =~ "package[nginx]"
      assert formatted =~ "changed"
    end

    test "formats skipped result" do
      result = Result.skipped("package[nginx]", "condition not met")
      formatted = DiffFormatter.format(result)

      assert formatted =~ "package[nginx]"
      assert formatted =~ "skipped"
    end

    test "formats failed result" do
      result = Result.failed("package[nginx]", "installation failed")
      formatted = DiffFormatter.format(result)

      assert formatted =~ "package[nginx]"
      assert formatted =~ "failed"
    end

    test "includes skip reason message" do
      result = Result.skipped("service[nginx]", "condition not met")
      formatted = DiffFormatter.format(result)

      assert formatted =~ "condition not met"
    end

    test "includes failure message" do
      result = Result.failed("command[test]", "exit code 1")
      formatted = DiffFormatter.format(result)

      assert formatted =~ "exit code 1"
    end
  end

  describe "format/2 with verbose option" do
    test "shows before/after diff details when verbose" do
      diff = %{
        before: %{installed: false},
        after: %{installed: true},
        changes: ["installed"]
      }

      result = Result.changed("package[nginx]", diff)
      formatted = DiffFormatter.format(result, verbose: true)

      assert formatted =~ "installed"
      assert formatted =~ "false"
      assert formatted =~ "true"
    end

    test "shows change list without before/after when not verbose" do
      diff = %{
        before: %{installed: false},
        after: %{installed: true},
        changes: ["installed"]
      }

      result = Result.changed("package[nginx]", diff)
      formatted = DiffFormatter.format(result, verbose: false)

      assert formatted =~ "package[nginx]"
      assert formatted =~ "installed"
    end
  end

  describe "format_all/2" do
    test "formats multiple results" do
      results = [
        Result.ok("package[nginx]"),
        Result.changed("service[nginx]", %{changes: ["started"]}),
        Result.skipped("file[/etc/motd]", "condition not met")
      ]

      formatted = DiffFormatter.format_all(results)

      assert formatted =~ "package[nginx]"
      assert formatted =~ "service[nginx]"
      assert formatted =~ "file[/etc/motd]"
    end

    test "handles empty results list" do
      formatted = DiffFormatter.format_all([])
      assert is_binary(formatted)
    end

    test "joins multiple results with newlines" do
      results = [
        Result.ok("package[nginx]"),
        Result.ok("package[curl]")
      ]

      formatted = DiffFormatter.format_all(results)

      assert formatted =~ "package[nginx]"
      assert formatted =~ "package[curl]"
    end
  end

  describe "format_summary/2" do
    test "shows count of each status" do
      results = [
        Result.ok("package[nginx]"),
        Result.ok("package[curl]"),
        Result.changed("service[nginx]", %{}),
        Result.skipped("file[/etc/motd]", "skipped"),
        Result.failed("command[test]", "failed")
      ]

      summary = DiffFormatter.format_summary(results)

      assert summary =~ "5 total"
      assert summary =~ "2 ok"
      assert summary =~ "1 changed"
    end

    test "shows duration" do
      results = [
        Result.ok("package[nginx]", duration_ms: 100),
        Result.changed("service[nginx]", %{}, duration_ms: 200)
      ]

      summary = DiffFormatter.format_summary(results)

      assert summary =~ "Duration"
    end

    test "handles empty results" do
      summary = DiffFormatter.format_summary([])
      assert summary =~ "0 total"
    end
  end

  describe "format_by_host/2" do
    test "groups results by host" do
      results = %{
        "host1" => [Result.ok("package[nginx]")],
        "host2" => [Result.changed("service[nginx]", %{})]
      }

      formatted = DiffFormatter.format_by_host(results)

      assert formatted =~ "host1"
      assert formatted =~ "host2"
    end

    test "handles empty host results" do
      results = %{
        "host1" => []
      }

      formatted = DiffFormatter.format_by_host(results)
      assert is_binary(formatted)
    end
  end

  describe "edge cases" do
    test "handles nil diff" do
      result = Result.ok("package[nginx]")
      formatted = DiffFormatter.format(result)

      assert is_binary(formatted)
    end

    test "handles empty changes list" do
      diff = %{changes: []}
      result = Result.changed("package[nginx]", diff)
      formatted = DiffFormatter.format(result)

      assert is_binary(formatted)
    end

    test "handles special characters in resource name" do
      result = Result.ok("file[/etc/nginx/sites-available/default]")
      formatted = DiffFormatter.format(result)

      assert formatted =~ "/etc/nginx/sites-available/default"
    end

    test "handles long error messages" do
      long_message = String.duplicate("error ", 100)
      result = Result.failed("command[test]", long_message)
      formatted = DiffFormatter.format(result)

      assert is_binary(formatted)
    end

    test "handles diff with action key" do
      diff = %{action: "started"}
      result = Result.changed("service[nginx]", diff)
      formatted = DiffFormatter.format(result)

      assert formatted =~ "started"
    end
  end
end

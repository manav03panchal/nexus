defmodule Nexus.Resources.ResultTest do
  use ExUnit.Case, async: true

  alias Nexus.Resources.Result

  describe "ok/2" do
    test "creates ok result with resource name" do
      result = Result.ok("package[nginx]")

      assert result.status == :ok
      assert result.resource == "package[nginx]"
      assert result.diff == nil
      assert result.message == nil
      assert result.notify == nil
      assert result.duration_ms == 0
    end

    test "creates ok result with message option" do
      result = Result.ok("service[nginx]", message: "already running")

      assert result.status == :ok
      assert result.message == "already running"
    end

    test "creates ok result with duration_ms option" do
      result = Result.ok("file[/etc/motd]", duration_ms: 150)

      assert result.status == :ok
      assert result.duration_ms == 150
    end

    test "creates ok result with multiple options" do
      result = Result.ok("directory[/var/app]", message: "exists", duration_ms: 25)

      assert result.status == :ok
      assert result.message == "exists"
      assert result.duration_ms == 25
    end
  end

  describe "changed/3" do
    test "creates changed result with resource and diff" do
      diff = %{before: %{installed: false}, after: %{installed: true}, changes: ["install"]}
      result = Result.changed("package[nginx]", diff)

      assert result.status == :changed
      assert result.resource == "package[nginx]"
      assert result.diff == diff
      assert result.message == nil
      assert result.notify == nil
      assert result.duration_ms == 0
    end

    test "creates changed result with message option" do
      diff = %{changes: ["updated content"]}
      result = Result.changed("file[/etc/motd]", diff, message: "content updated")

      assert result.status == :changed
      assert result.message == "content updated"
    end

    test "creates changed result with notify option" do
      diff = %{changes: ["updated config"]}
      result = Result.changed("file[/etc/nginx.conf]", diff, notify: :restart_nginx)

      assert result.status == :changed
      assert result.notify == :restart_nginx
    end

    test "creates changed result with duration_ms option" do
      diff = %{changes: ["created"]}
      result = Result.changed("directory[/var/app]", diff, duration_ms: 300)

      assert result.status == :changed
      assert result.duration_ms == 300
    end

    test "creates changed result with all options" do
      diff = %{before: %{}, after: %{}, changes: ["installed"]}

      result =
        Result.changed("package[curl]", diff,
          message: "installed successfully",
          notify: :reload_app,
          duration_ms: 500
        )

      assert result.status == :changed
      assert result.diff == diff
      assert result.message == "installed successfully"
      assert result.notify == :reload_app
      assert result.duration_ms == 500
    end

    test "handles empty diff map" do
      result = Result.changed("command[echo]", %{})

      assert result.status == :changed
      assert result.diff == %{}
    end
  end

  describe "failed/3" do
    test "creates failed result with resource and message" do
      result = Result.failed("package[nginx]", "apt-get returned exit code 100")

      assert result.status == :failed
      assert result.resource == "package[nginx]"
      assert result.message == "apt-get returned exit code 100"
      assert result.diff == nil
      assert result.duration_ms == 0
    end

    test "creates failed result with duration_ms option" do
      result = Result.failed("command[make]", "build failed", duration_ms: 5000)

      assert result.status == :failed
      assert result.duration_ms == 5000
    end

    test "creates failed result with partial diff option" do
      partial_diff = %{before: %{exists: true}, changes: []}
      result = Result.failed("file[/etc/config]", "permission denied", diff: partial_diff)

      assert result.status == :failed
      assert result.diff == partial_diff
    end

    test "handles empty error message" do
      result = Result.failed("command[test]", "")

      assert result.status == :failed
      assert result.message == ""
    end
  end

  describe "skipped/2" do
    test "creates skipped result with resource and reason" do
      result = Result.skipped("package[nginx]", "condition not met")

      assert result.status == :skipped
      assert result.resource == "package[nginx]"
      assert result.message == "condition not met"
      assert result.diff == nil
      assert result.notify == nil
      assert result.duration_ms == 0
    end

    test "skipped result always has zero duration" do
      result = Result.skipped("service[app]", "dependency failed")

      assert result.duration_ms == 0
    end
  end

  describe "changed?/1" do
    test "returns true for changed status" do
      result = Result.changed("test", %{})
      assert Result.changed?(result) == true
    end

    test "returns false for ok status" do
      result = Result.ok("test")
      assert Result.changed?(result) == false
    end

    test "returns false for failed status" do
      result = Result.failed("test", "error")
      assert Result.changed?(result) == false
    end

    test "returns false for skipped status" do
      result = Result.skipped("test", "reason")
      assert Result.changed?(result) == false
    end
  end

  describe "success?/1" do
    test "returns true for ok status" do
      result = Result.ok("test")
      assert Result.success?(result) == true
    end

    test "returns true for changed status" do
      result = Result.changed("test", %{})
      assert Result.success?(result) == true
    end

    test "returns false for failed status" do
      result = Result.failed("test", "error")
      assert Result.success?(result) == false
    end

    test "returns false for skipped status" do
      result = Result.skipped("test", "reason")
      assert Result.success?(result) == false
    end
  end

  describe "failed?/1" do
    test "returns true for failed status" do
      result = Result.failed("test", "error")
      assert Result.failed?(result) == true
    end

    test "returns false for ok status" do
      result = Result.ok("test")
      assert Result.failed?(result) == false
    end

    test "returns false for changed status" do
      result = Result.changed("test", %{})
      assert Result.failed?(result) == false
    end

    test "returns false for skipped status" do
      result = Result.skipped("test", "reason")
      assert Result.failed?(result) == false
    end
  end

  describe "struct validation" do
    test "enforces required fields" do
      result = %Result{resource: "test", status: :ok}
      assert result.resource == "test"
      assert result.status == :ok
    end

    test "has default values for optional fields" do
      result = %Result{resource: "test", status: :ok}
      assert result.diff == nil
      assert result.message == nil
      assert result.notify == nil
      assert result.duration_ms == 0
    end
  end
end

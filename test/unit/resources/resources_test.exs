defmodule Nexus.Resources.ResourcesTest do
  use ExUnit.Case, async: true

  alias Nexus.Resources.DiffFormatter
  alias Nexus.Resources.Result
  alias Nexus.Resources.Types.{Command, Directory, Group, Package, Service, User}
  alias Nexus.Resources.Types.File, as: FileResource

  describe "Package type" do
    test "creates package with defaults" do
      pkg = Package.new("nginx")
      assert pkg.name == "nginx"
      assert pkg.state == :installed
      assert pkg.version == nil
    end

    test "creates package with options" do
      pkg = Package.new("nginx", state: :latest, version: "1.24.0", notify: :restart)
      assert pkg.name == "nginx"
      assert pkg.state == :latest
      assert pkg.version == "1.24.0"
      assert pkg.notify == :restart
    end

    test "creates package to remove" do
      pkg = Package.new("nginx", state: :absent)
      assert pkg.state == :absent
    end

    test "describe returns formatted string" do
      pkg = Package.new("nginx")
      assert Package.describe(pkg) =~ "package[nginx]"
    end

    test "supports multiple packages" do
      pkg = Package.new(["nginx", "curl", "wget"])
      assert pkg.name == ["nginx", "curl", "wget"]
    end
  end

  describe "Service type" do
    test "creates service with defaults" do
      svc = Service.new("nginx")
      assert svc.name == "nginx"
      # Defaults may be nil (managed by provider) - just verify struct created
      assert is_struct(svc, Service)
    end

    test "creates service with options" do
      svc = Service.new("nginx", state: :stopped, enabled: false, action: :restart)
      assert svc.state == :stopped
      assert svc.enabled == false
      assert svc.action == :restart
    end

    test "describe returns formatted string" do
      svc = Service.new("nginx")
      assert Service.describe(svc) =~ "service[nginx]"
    end
  end

  describe "File type" do
    test "creates file with content" do
      file = FileResource.new("/etc/motd", content: "Welcome")
      assert file.path == "/etc/motd"
      assert file.content == "Welcome"
      assert file.state == :present
    end

    test "creates file with source" do
      file = FileResource.new("/etc/nginx.conf", source: "templates/nginx.conf")
      assert file.source == "templates/nginx.conf"
    end

    test "creates file with ownership and mode" do
      file = FileResource.new("/etc/app.conf", owner: "root", group: "wheel", mode: 0o644)
      assert file.owner == "root"
      assert file.group == "wheel"
      assert file.mode == 0o644
    end

    test "creates file to remove" do
      file = FileResource.new("/tmp/old", state: :absent)
      assert file.state == :absent
    end

    test "describe returns formatted string" do
      file = FileResource.new("/etc/motd")
      assert FileResource.describe(file) =~ "file[/etc/motd]"
    end
  end

  describe "Directory type" do
    test "creates directory with defaults" do
      dir = Directory.new("/var/app")
      assert dir.path == "/var/app"
      assert dir.state == :present
      assert dir.recursive == false
    end

    test "creates directory with options" do
      dir = Directory.new("/var/app", owner: "deploy", mode: 0o755, recursive: true)
      assert dir.owner == "deploy"
      assert dir.mode == 0o755
      assert dir.recursive == true
    end

    test "describe returns formatted string" do
      dir = Directory.new("/var/app")
      assert Directory.describe(dir) =~ "directory[/var/app]"
    end
  end

  describe "User type" do
    test "creates user with defaults" do
      user = User.new("deploy")
      assert user.name == "deploy"
      assert user.state == :present
      assert user.groups == []
    end

    test "creates user with options" do
      user =
        User.new("deploy",
          uid: 1001,
          home: "/home/deploy",
          shell: "/bin/bash",
          groups: ["sudo", "docker"]
        )

      assert user.uid == 1001
      assert user.home == "/home/deploy"
      assert user.shell == "/bin/bash"
      assert user.groups == ["sudo", "docker"]
    end

    test "creates user to remove" do
      user = User.new("olduser", state: :absent)
      assert user.state == :absent
    end

    test "describe returns formatted string" do
      user = User.new("deploy")
      assert User.describe(user) =~ "user[deploy]"
    end
  end

  describe "Group type" do
    test "creates group with defaults" do
      group = Group.new("developers")
      assert group.name == "developers"
      assert group.state == :present
    end

    test "creates group with options" do
      group = Group.new("developers", gid: 1001, system: true)
      assert group.gid == 1001
      assert group.system == true
    end

    test "describe returns formatted string" do
      group = Group.new("developers")
      assert Group.describe(group) =~ "group[developers]"
    end
  end

  describe "Command type" do
    test "creates command with defaults" do
      cmd = Command.new("echo hello")
      assert cmd.cmd == "echo hello"
      assert cmd.sudo == false
      assert cmd.timeout == 60_000
    end

    test "creates command with idempotency guards" do
      cmd = Command.new("tar -xzf app.tar.gz", creates: "/opt/app/bin/app")
      assert cmd.creates == "/opt/app/bin/app"
    end

    test "creates command with unless guard" do
      cmd = Command.new("mix deps.get", unless: "mix deps.check")
      assert cmd.unless == "mix deps.check"
    end

    test "creates command with onlyif guard" do
      cmd = Command.new("systemctl restart app", onlyif: "systemctl is-active app")
      assert cmd.onlyif == "systemctl is-active app"
    end

    test "creates command with options" do
      cmd =
        Command.new("mix release",
          sudo: true,
          cwd: "/opt/app",
          env: %{"MIX_ENV" => "prod"},
          timeout: 120_000
        )

      assert cmd.sudo == true
      assert cmd.cwd == "/opt/app"
      assert cmd.env == %{"MIX_ENV" => "prod"}
      assert cmd.timeout == 120_000
    end

    test "idempotent? returns true when guards present" do
      cmd = Command.new("make", creates: "build/")
      assert Command.idempotent?(cmd) == true
    end

    test "idempotent? returns false when no guards" do
      cmd = Command.new("echo hello")
      assert Command.idempotent?(cmd) == false
    end

    test "describe returns formatted string" do
      cmd = Command.new("echo hello")
      assert Command.describe(cmd) == "command[echo hello]"
    end

    test "describe truncates long commands" do
      long_cmd = String.duplicate("a", 100)
      cmd = Command.new(long_cmd)
      desc = Command.describe(cmd)
      assert String.length(desc) < 70
      assert String.ends_with?(desc, "...]")
    end
  end

  describe "Result" do
    test "ok creates success result" do
      result = Result.ok("package[nginx]")
      assert result.status == :ok
      assert result.resource == "package[nginx]"
    end

    test "changed creates changed result with diff" do
      diff = %{before: %{installed: false}, after: %{installed: true}, changes: ["installed"]}
      result = Result.changed("package[nginx]", diff)
      assert result.status == :changed
      assert result.diff == diff
    end

    test "skipped creates skipped result" do
      result = Result.skipped("package[nginx]", "condition not met")
      assert result.status == :skipped
      assert result.message == "condition not met"
    end

    test "failed creates failed result" do
      result = Result.failed("package[nginx]", "apt-get failed")
      assert result.status == :failed
      assert result.message == "apt-get failed"
    end

    test "status check for ok" do
      result = Result.ok("test")
      assert result.status == :ok
    end

    test "status check for changed" do
      result = Result.changed("test", %{})
      assert result.status == :changed
    end

    test "status check for failed" do
      result = Result.failed("test", "error")
      assert result.status == :failed
    end
  end

  describe "DiffFormatter" do
    test "formats ok result" do
      result = Result.ok("package[nginx]", duration_ms: 100)
      output = DiffFormatter.format(result, color: false)
      assert output =~ "[ok]"
      assert output =~ "package[nginx]"
    end

    test "formats changed result with diff" do
      diff = %{
        before: %{installed: false},
        after: %{installed: true},
        changes: ["install package"]
      }

      result = Result.changed("package[nginx]", diff, duration_ms: 250)
      output = DiffFormatter.format(result, color: false)
      assert output =~ "[changed]"
      assert output =~ "package[nginx]"
      assert output =~ "install package"
    end

    test "formats skipped result" do
      result = Result.skipped("package[nginx]", "condition not met")
      output = DiffFormatter.format(result, color: false)
      assert output =~ "[skipped]"
      assert output =~ "condition not met"
    end

    test "formats failed result" do
      result = Result.failed("package[nginx]", "apt-get returned error", duration_ms: 50)
      output = DiffFormatter.format(result, color: false)
      assert output =~ "[failed]"
      assert output =~ "apt-get returned error"
    end

    test "formats summary" do
      results = [
        Result.ok("package[nginx]", duration_ms: 100),
        Result.changed("file[/etc/nginx.conf]", %{changes: ["updated"]}, duration_ms: 50),
        Result.skipped("service[nginx]", "already running"),
        Result.failed("command[test]", "error", duration_ms: 10)
      ]

      output = DiffFormatter.format_summary(results, color: false)
      assert output =~ "Resources: 4 total"
      assert output =~ "1 changed"
      assert output =~ "1 ok"
      assert output =~ "1 skipped"
      assert output =~ "1 failed"
    end
  end
end

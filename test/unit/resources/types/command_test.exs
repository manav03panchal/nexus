defmodule Nexus.Resources.Types.CommandTest do
  use ExUnit.Case, async: true

  alias Nexus.Resources.Types.Command

  describe "new/1" do
    test "creates command with just cmd and defaults" do
      cmd = Command.new("echo hello")

      assert cmd.cmd == "echo hello"
      assert cmd.creates == nil
      assert cmd.removes == nil
      assert cmd.unless == nil
      assert cmd.onlyif == nil
      assert cmd.sudo == false
      assert cmd.user == nil
      assert cmd.cwd == nil
      assert cmd.env == %{}
      assert cmd.timeout == 60_000
      assert cmd.notify == nil
      assert cmd.when == true
    end
  end

  describe "new/2" do
    test "creates command with creates guard" do
      cmd = Command.new("tar -xzf app.tar.gz", creates: "/opt/app/bin/app")

      assert cmd.creates == "/opt/app/bin/app"
    end

    test "creates command with removes guard" do
      cmd = Command.new("rm -rf /tmp/cache", removes: "/tmp/cache")

      assert cmd.removes == "/tmp/cache"
    end

    test "creates command with unless guard" do
      cmd = Command.new("mix deps.get", unless: "mix deps.check")

      assert cmd.unless == "mix deps.check"
    end

    test "creates command with onlyif guard" do
      cmd = Command.new("systemctl restart app", onlyif: "systemctl is-active app")

      assert cmd.onlyif == "systemctl is-active app"
    end

    test "creates command with sudo" do
      cmd = Command.new("systemctl restart nginx", sudo: true)

      assert cmd.sudo == true
    end

    test "creates command with user" do
      cmd = Command.new("mix release", user: "deploy")

      assert cmd.user == "deploy"
    end

    test "creates command with cwd" do
      cmd = Command.new("mix release", cwd: "/opt/app")

      assert cmd.cwd == "/opt/app"
    end

    test "creates command with env" do
      cmd = Command.new("mix release", env: %{"MIX_ENV" => "prod", "PORT" => "8080"})

      assert cmd.env == %{"MIX_ENV" => "prod", "PORT" => "8080"}
    end

    test "creates command with timeout" do
      cmd = Command.new("long_running_script.sh", timeout: 300_000)

      assert cmd.timeout == 300_000
    end

    test "creates command with notify" do
      cmd = Command.new("nginx -t", notify: :reload_nginx)

      assert cmd.notify == :reload_nginx
    end

    test "creates command with when condition" do
      condition = {:==, :os, :linux}
      cmd = Command.new("systemctl start app", when: condition)

      assert cmd.when == condition
    end

    test "creates command with all options" do
      cmd =
        Command.new("mix release",
          creates: "/opt/app/_build/prod/rel/app",
          unless: "test -d /opt/app/_build/prod/rel/app",
          sudo: true,
          user: "deploy",
          cwd: "/opt/app",
          env: %{"MIX_ENV" => "prod"},
          timeout: 120_000,
          notify: :restart_app,
          when: {:==, :env, :production}
        )

      assert cmd.cmd == "mix release"
      assert cmd.creates == "/opt/app/_build/prod/rel/app"
      assert cmd.unless == "test -d /opt/app/_build/prod/rel/app"
      assert cmd.sudo == true
      assert cmd.user == "deploy"
      assert cmd.cwd == "/opt/app"
      assert cmd.env == %{"MIX_ENV" => "prod"}
      assert cmd.timeout == 120_000
      assert cmd.notify == :restart_app
      assert cmd.when == {:==, :env, :production}
    end

    test "creates command with multiple idempotency guards" do
      cmd =
        Command.new("setup.sh",
          creates: "/opt/app/.setup_complete",
          onlyif: "test -f /opt/app/setup.sh"
        )

      assert cmd.creates == "/opt/app/.setup_complete"
      assert cmd.onlyif == "test -f /opt/app/setup.sh"
    end
  end

  describe "describe/1" do
    test "describes short command" do
      cmd = Command.new("echo hello")
      desc = Command.describe(cmd)

      assert desc == "command[echo hello]"
    end

    test "describes command exactly 50 characters" do
      long_cmd = String.duplicate("a", 50)
      cmd = Command.new(long_cmd)
      desc = Command.describe(cmd)

      assert desc == "command[#{long_cmd}]"
    end

    test "truncates command longer than 50 characters" do
      long_cmd = String.duplicate("a", 100)
      cmd = Command.new(long_cmd)
      desc = Command.describe(cmd)

      expected = "command[#{String.slice(long_cmd, 0, 47)}...]"
      assert desc == expected
    end

    test "describes empty command" do
      cmd = Command.new("")
      desc = Command.describe(cmd)

      assert desc == "command[]"
    end
  end

  describe "idempotent?/1" do
    test "returns true when creates is set" do
      cmd = Command.new("make", creates: "build/")

      assert Command.idempotent?(cmd) == true
    end

    test "returns true when removes is set" do
      cmd = Command.new("rm -rf cache/", removes: "cache/")

      assert Command.idempotent?(cmd) == true
    end

    test "returns true when unless is set" do
      cmd = Command.new("mix deps.get", unless: "mix deps.check")

      assert Command.idempotent?(cmd) == true
    end

    test "returns true when onlyif is set" do
      cmd = Command.new("systemctl restart app", onlyif: "systemctl is-active app")

      assert Command.idempotent?(cmd) == true
    end

    test "returns true when multiple guards are set" do
      cmd =
        Command.new("setup.sh", creates: "/opt/app/.done", onlyif: "test -f /opt/app/setup.sh")

      assert Command.idempotent?(cmd) == true
    end

    test "returns false when no guards are set" do
      cmd = Command.new("echo hello")

      assert Command.idempotent?(cmd) == false
    end

    test "returns false for command with only non-guard options" do
      cmd = Command.new("echo hello", sudo: true, cwd: "/tmp", timeout: 5000)

      assert Command.idempotent?(cmd) == false
    end
  end

  describe "struct" do
    test "enforces :cmd as required key" do
      assert_raise ArgumentError, fn ->
        struct!(Command, [])
      end
    end

    test "has correct default values" do
      cmd = struct!(Command, cmd: "test")

      assert cmd.sudo == false
      assert cmd.env == %{}
      assert cmd.timeout == 60_000
      assert cmd.when == true
    end
  end
end

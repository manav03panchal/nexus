defmodule Nexus.Resources.Types.DirectoryTest do
  use ExUnit.Case, async: true

  alias Nexus.Resources.Types.Directory

  describe "new/1" do
    test "creates directory with just path and defaults" do
      dir = Directory.new("/var/www/app")

      assert dir.path == "/var/www/app"
      assert dir.state == :present
      assert dir.owner == nil
      assert dir.group == nil
      assert dir.mode == nil
      assert dir.recursive == false
      assert dir.notify == nil
      assert dir.when == true
    end
  end

  describe "new/2" do
    test "creates directory with :present state" do
      dir = Directory.new("/var/app", state: :present)

      assert dir.state == :present
    end

    test "creates directory with :absent state" do
      dir = Directory.new("/tmp/cache", state: :absent)

      assert dir.state == :absent
    end

    test "creates directory with owner" do
      dir = Directory.new("/var/www/app", owner: "www-data")

      assert dir.owner == "www-data"
    end

    test "creates directory with group" do
      dir = Directory.new("/var/www/app", group: "www-data")

      assert dir.group == "www-data"
    end

    test "creates directory with mode" do
      dir = Directory.new("/var/www/app", mode: 0o755)

      assert dir.mode == 0o755
    end

    test "creates directory with different mode values" do
      dir1 = Directory.new("/opt/app", mode: 0o700)
      dir2 = Directory.new("/opt/public", mode: 0o777)
      dir3 = Directory.new("/opt/secure", mode: 0o600)

      assert dir1.mode == 0o700
      assert dir2.mode == 0o777
      assert dir3.mode == 0o600
    end

    test "creates directory with recursive option" do
      dir = Directory.new("/opt/app/releases/v1.0.0", recursive: true)

      assert dir.recursive == true
    end

    test "creates directory with notify option" do
      dir = Directory.new("/var/app", notify: :set_permissions)

      assert dir.notify == :set_permissions
    end

    test "creates directory with when condition" do
      condition = {:==, :os, :linux}
      dir = Directory.new("/opt/app", when: condition)

      assert dir.when == condition
    end

    test "creates directory with all options" do
      dir =
        Directory.new("/var/www/app",
          state: :present,
          owner: "www-data",
          group: "www-data",
          mode: 0o755,
          recursive: true,
          notify: :restart_app,
          when: {:!=, :os, :windows}
        )

      assert dir.path == "/var/www/app"
      assert dir.state == :present
      assert dir.owner == "www-data"
      assert dir.group == "www-data"
      assert dir.mode == 0o755
      assert dir.recursive == true
      assert dir.notify == :restart_app
      assert dir.when == {:!=, :os, :windows}
    end
  end

  describe "describe/1" do
    test "describes directory with present state" do
      dir = Directory.new("/var/www/app")
      desc = Directory.describe(dir)

      assert desc == "directory[/var/www/app] state=present"
    end

    test "describes directory with absent state" do
      dir = Directory.new("/tmp/cache", state: :absent)
      desc = Directory.describe(dir)

      assert desc == "directory[/tmp/cache] state=absent"
    end

    test "describes root directory" do
      dir = Directory.new("/")
      desc = Directory.describe(dir)

      assert desc == "directory[/] state=present"
    end

    test "describes deeply nested path" do
      dir = Directory.new("/opt/app/releases/v1.0.0/lib/myapp")
      desc = Directory.describe(dir)

      assert desc == "directory[/opt/app/releases/v1.0.0/lib/myapp] state=present"
    end
  end

  describe "struct" do
    test "enforces :path as required key" do
      assert_raise ArgumentError, fn ->
        struct!(Directory, [])
      end
    end

    test "has correct default values" do
      dir = struct!(Directory, path: "/test")

      assert dir.state == :present
      assert dir.recursive == false
      assert dir.when == true
    end
  end
end

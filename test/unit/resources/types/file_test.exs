defmodule Nexus.Resources.Types.FileTest do
  use ExUnit.Case, async: true

  alias Nexus.Resources.Types.File, as: FileResource

  describe "new/1" do
    test "creates file with just path and defaults" do
      file = FileResource.new("/etc/motd")

      assert file.path == "/etc/motd"
      assert file.state == :present
      assert file.source == nil
      assert file.content == nil
      assert file.owner == nil
      assert file.group == nil
      assert file.mode == nil
      assert file.vars == %{}
      assert file.backup == true
      assert file.notify == nil
      assert file.when == true
    end
  end

  describe "new/2" do
    test "creates file with :present state" do
      file = FileResource.new("/etc/config", state: :present)

      assert file.state == :present
    end

    test "creates file with :absent state" do
      file = FileResource.new("/tmp/old_file", state: :absent)

      assert file.state == :absent
    end

    test "creates file with source" do
      file = FileResource.new("/etc/nginx/nginx.conf", source: "templates/nginx.conf")

      assert file.source == "templates/nginx.conf"
    end

    test "creates file with template source" do
      file = FileResource.new("/etc/nginx/nginx.conf", source: "templates/nginx.conf.eex")

      assert file.source == "templates/nginx.conf.eex"
    end

    test "creates file with content" do
      file = FileResource.new("/etc/motd", content: "Welcome to the server!")

      assert file.content == "Welcome to the server!"
    end

    test "creates file with multiline content" do
      content = """
      Welcome to the server!
      Please follow the rules.
      """

      file = FileResource.new("/etc/motd", content: content)

      assert file.content == content
    end

    test "creates file with owner" do
      file = FileResource.new("/etc/app.conf", owner: "root")

      assert file.owner == "root"
    end

    test "creates file with group" do
      file = FileResource.new("/etc/app.conf", group: "wheel")

      assert file.group == "wheel"
    end

    test "creates file with mode" do
      file = FileResource.new("/etc/app.conf", mode: 0o644)

      assert file.mode == 0o644
    end

    test "creates file with different mode values" do
      file1 = FileResource.new("/etc/secret", mode: 0o600)
      file2 = FileResource.new("/usr/bin/script", mode: 0o755)

      assert file1.mode == 0o600
      assert file2.mode == 0o755
    end

    test "creates file with vars" do
      file =
        FileResource.new("/etc/nginx/nginx.conf",
          source: "nginx.conf.eex",
          vars: %{port: 8080, workers: 4}
        )

      assert file.vars == %{port: 8080, workers: 4}
    end

    test "creates file with backup disabled" do
      file = FileResource.new("/etc/config", backup: false)

      assert file.backup == false
    end

    test "creates file with notify" do
      file = FileResource.new("/etc/nginx/nginx.conf", notify: :reload_nginx)

      assert file.notify == :reload_nginx
    end

    test "creates file with when condition" do
      condition = {:==, :os, :linux}
      file = FileResource.new("/etc/app.conf", when: condition)

      assert file.when == condition
    end

    test "creates file with all options" do
      file =
        FileResource.new("/etc/nginx/nginx.conf",
          state: :present,
          source: "templates/nginx.conf.eex",
          owner: "root",
          group: "root",
          mode: 0o644,
          vars: %{port: 8080, workers: 4},
          backup: true,
          notify: :reload_nginx,
          when: {:==, :os, :linux}
        )

      assert file.path == "/etc/nginx/nginx.conf"
      assert file.state == :present
      assert file.source == "templates/nginx.conf.eex"
      assert file.owner == "root"
      assert file.group == "root"
      assert file.mode == 0o644
      assert file.vars == %{port: 8080, workers: 4}
      assert file.backup == true
      assert file.notify == :reload_nginx
      assert file.when == {:==, :os, :linux}
    end
  end

  describe "describe/1" do
    test "describes file with present state" do
      file = FileResource.new("/etc/motd")
      desc = FileResource.describe(file)

      assert desc == "file[/etc/motd] state=present"
    end

    test "describes file with absent state" do
      file = FileResource.new("/tmp/old", state: :absent)
      desc = FileResource.describe(file)

      assert desc == "file[/tmp/old] state=absent"
    end

    test "describes file in root" do
      file = FileResource.new("/config")
      desc = FileResource.describe(file)

      assert desc == "file[/config] state=present"
    end

    test "describes file with long path" do
      file = FileResource.new("/opt/app/config/environments/production/settings.yml")
      desc = FileResource.describe(file)

      assert desc == "file[/opt/app/config/environments/production/settings.yml] state=present"
    end
  end

  describe "template?/1" do
    test "returns true for .eex template source" do
      file = FileResource.new("/etc/nginx/nginx.conf", source: "templates/nginx.conf.eex")

      assert FileResource.template?(file) == true
    end

    test "returns false for non-template source" do
      file = FileResource.new("/etc/nginx/nginx.conf", source: "configs/nginx.conf")

      assert FileResource.template?(file) == false
    end

    test "returns false when source is nil" do
      file = FileResource.new("/etc/motd", content: "Hello")

      assert FileResource.template?(file) == false
    end

    test "returns false for source with eex in middle of name" do
      file = FileResource.new("/etc/config", source: "templates/eex_config.txt")

      assert FileResource.template?(file) == false
    end

    test "returns true for nested template path" do
      file = FileResource.new("/etc/app/config", source: "templates/app/config.json.eex")

      assert FileResource.template?(file) == true
    end

    test "returns false for file with content only" do
      file = FileResource.new("/etc/motd", content: "Welcome")

      assert FileResource.template?(file) == false
    end
  end

  describe "struct" do
    test "enforces :path as required key" do
      assert_raise ArgumentError, fn ->
        struct!(FileResource, [])
      end
    end

    test "has correct default values" do
      file = struct!(FileResource, path: "/test")

      assert file.state == :present
      assert file.vars == %{}
      assert file.backup == true
      assert file.when == true
    end
  end
end

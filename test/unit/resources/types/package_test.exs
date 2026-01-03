defmodule Nexus.Resources.Types.PackageTest do
  use ExUnit.Case, async: true

  alias Nexus.Resources.Types.Package

  describe "new/1" do
    test "creates package with just name and defaults" do
      pkg = Package.new("nginx")

      assert pkg.name == "nginx"
      assert pkg.state == :installed
      assert pkg.version == nil
      assert pkg.update_cache == false
      assert pkg.notify == nil
      assert pkg.when == true
    end

    test "creates package with list of names" do
      pkg = Package.new(["nginx", "curl", "git"])

      assert pkg.name == ["nginx", "curl", "git"]
      assert pkg.state == :installed
    end

    test "creates package with empty list of names" do
      pkg = Package.new([])

      assert pkg.name == []
    end
  end

  describe "new/2" do
    test "creates package with :installed state" do
      pkg = Package.new("nginx", state: :installed)

      assert pkg.state == :installed
    end

    test "creates package with :absent state" do
      pkg = Package.new("nginx", state: :absent)

      assert pkg.state == :absent
    end

    test "creates package with :latest state" do
      pkg = Package.new("nginx", state: :latest)

      assert pkg.state == :latest
    end

    test "creates package with specific version" do
      pkg = Package.new("nginx", version: "1.18.0")

      assert pkg.version == "1.18.0"
    end

    test "creates package with update_cache option" do
      pkg = Package.new("nginx", update_cache: true)

      assert pkg.update_cache == true
    end

    test "creates package with notify option" do
      pkg = Package.new("nginx", notify: :restart_nginx)

      assert pkg.notify == :restart_nginx
    end

    test "creates package with when condition" do
      condition = {:==, :os_family, :debian}
      pkg = Package.new("nginx", when: condition)

      assert pkg.when == condition
    end

    test "creates package with all options" do
      pkg =
        Package.new("nginx",
          state: :latest,
          version: "1.24.0",
          update_cache: true,
          notify: :reload_config,
          when: {:==, :os, :linux}
        )

      assert pkg.name == "nginx"
      assert pkg.state == :latest
      assert pkg.version == "1.24.0"
      assert pkg.update_cache == true
      assert pkg.notify == :reload_config
      assert pkg.when == {:==, :os, :linux}
    end

    test "creates package with multiple packages and options" do
      pkg = Package.new(["nginx", "curl"], state: :installed, update_cache: true)

      assert pkg.name == ["nginx", "curl"]
      assert pkg.state == :installed
      assert pkg.update_cache == true
    end
  end

  describe "describe/1" do
    test "describes single package without version" do
      pkg = Package.new("nginx")
      desc = Package.describe(pkg)

      assert desc == "package[nginx] state=installed"
    end

    test "describes single package with version" do
      pkg = Package.new("nginx", version: "1.18.0")
      desc = Package.describe(pkg)

      assert desc == "package[nginx] state=installed version=1.18.0"
    end

    test "describes package with absent state" do
      pkg = Package.new("nginx", state: :absent)
      desc = Package.describe(pkg)

      assert desc == "package[nginx] state=absent"
    end

    test "describes package with latest state and version" do
      pkg = Package.new("nginx", state: :latest, version: "1.24.0")
      desc = Package.describe(pkg)

      assert desc == "package[nginx] state=latest version=1.24.0"
    end

    test "describes multiple packages without version" do
      pkg = Package.new(["nginx", "curl", "git"])
      desc = Package.describe(pkg)

      assert desc == "package[nginx, curl, git] state=installed"
    end

    test "describes multiple packages with version" do
      pkg = Package.new(["nginx", "curl"], version: "latest")
      desc = Package.describe(pkg)

      assert desc == "package[nginx, curl] state=installed version=latest"
    end

    test "describes empty package list" do
      pkg = Package.new([])
      desc = Package.describe(pkg)

      assert desc == "package[] state=installed"
    end
  end

  describe "struct" do
    test "enforces :name as required key" do
      assert_raise ArgumentError, fn ->
        struct!(Package, [])
      end
    end

    test "allows creation with only name" do
      pkg = struct!(Package, name: "nginx")

      assert pkg.name == "nginx"
      assert pkg.state == :installed
    end

    test "has correct default values" do
      pkg = struct!(Package, name: "test")

      assert pkg.state == :installed
      assert pkg.update_cache == false
      assert pkg.version == nil
      assert pkg.notify == nil
      assert pkg.when == true
    end
  end
end

defmodule Nexus.Resources.Types.UserTest do
  use ExUnit.Case, async: true

  alias Nexus.Resources.Types.User

  describe "new/1" do
    test "creates user with just name and defaults" do
      user = User.new("deploy")

      assert user.name == "deploy"
      assert user.state == :present
      assert user.uid == nil
      assert user.gid == nil
      assert user.groups == []
      assert user.shell == nil
      assert user.home == nil
      assert user.comment == nil
      assert user.system == false
      assert user.notify == nil
      assert user.when == true
    end

    test "creates user with underscore prefix" do
      user = User.new("_nginx")

      assert user.name == "_nginx"
    end
  end

  describe "new/2" do
    test "creates user with :present state" do
      user = User.new("deploy", state: :present)

      assert user.state == :present
    end

    test "creates user with :absent state" do
      user = User.new("olduser", state: :absent)

      assert user.state == :absent
    end

    test "creates user with uid" do
      user = User.new("deploy", uid: 1001)

      assert user.uid == 1001
    end

    test "creates user with gid" do
      user = User.new("deploy", gid: 1001)

      assert user.gid == 1001
    end

    test "creates user with groups" do
      user = User.new("deploy", groups: ["sudo", "docker", "www-data"])

      assert user.groups == ["sudo", "docker", "www-data"]
    end

    test "creates user with shell" do
      user = User.new("deploy", shell: "/bin/bash")

      assert user.shell == "/bin/bash"
    end

    test "creates user with home directory" do
      user = User.new("deploy", home: "/home/deploy")

      assert user.home == "/home/deploy"
    end

    test "creates user with comment" do
      user = User.new("deploy", comment: "Deployment User")

      assert user.comment == "Deployment User"
    end

    test "creates system user" do
      user = User.new("app", system: true)

      assert user.system == true
    end

    test "creates user with notify option" do
      user = User.new("deploy", notify: :setup_user)

      assert user.notify == :setup_user
    end

    test "creates user with when condition" do
      condition = {:==, :os, :linux}
      user = User.new("deploy", when: condition)

      assert user.when == condition
    end

    test "creates user with all options" do
      user =
        User.new("deploy",
          state: :present,
          uid: 1001,
          gid: 1001,
          groups: ["sudo", "docker"],
          shell: "/bin/bash",
          home: "/home/deploy",
          comment: "Deployment User",
          system: false,
          notify: :setup_user,
          when: {:==, :os, :linux}
        )

      assert user.name == "deploy"
      assert user.state == :present
      assert user.uid == 1001
      assert user.gid == 1001
      assert user.groups == ["sudo", "docker"]
      assert user.shell == "/bin/bash"
      assert user.home == "/home/deploy"
      assert user.comment == "Deployment User"
      assert user.system == false
      assert user.notify == :setup_user
      assert user.when == {:==, :os, :linux}
    end

    test "creates user with nologin shell" do
      user = User.new("app", shell: "/usr/sbin/nologin", system: true)

      assert user.shell == "/usr/sbin/nologin"
      assert user.system == true
    end
  end

  describe "describe/1" do
    test "describes user without groups" do
      user = User.new("deploy")
      desc = User.describe(user)

      assert desc == "user[deploy] state=present"
    end

    test "describes user with groups" do
      user = User.new("deploy", groups: ["sudo", "docker"])
      desc = User.describe(user)

      assert desc =~ "user[deploy]"
      assert desc =~ "state=present"
    end

    test "describes user with absent state" do
      user = User.new("olduser", state: :absent)
      desc = User.describe(user)

      assert desc == "user[olduser] state=absent"
    end

    test "describes user with empty groups list" do
      user = User.new("deploy", groups: [])
      desc = User.describe(user)

      assert desc == "user[deploy] state=present"
    end
  end

  describe "struct" do
    test "enforces :name as required key" do
      assert_raise ArgumentError, fn ->
        struct!(User, [])
      end
    end

    test "has correct default values" do
      user = struct!(User, name: "test")

      assert user.state == :present
      assert user.groups == []
      assert user.system == false
      assert user.when == true
    end
  end
end

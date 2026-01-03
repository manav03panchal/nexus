defmodule Nexus.Resources.Types.GroupTest do
  use ExUnit.Case, async: true

  alias Nexus.Resources.Types.Group

  describe "new/1" do
    test "creates group with just name and defaults" do
      group = Group.new("developers")

      assert group.name == "developers"
      assert group.state == :present
      assert group.gid == nil
      assert group.system == false
      assert group.notify == nil
      assert group.when == true
    end
  end

  describe "new/2" do
    test "creates group with :present state" do
      group = Group.new("developers", state: :present)

      assert group.state == :present
    end

    test "creates group with :absent state" do
      group = Group.new("oldgroup", state: :absent)

      assert group.state == :absent
    end

    test "creates group with gid" do
      group = Group.new("developers", gid: 1001)

      assert group.gid == 1001
    end

    test "creates group with gid 0" do
      group = Group.new("root", gid: 0)

      assert group.gid == 0
    end

    test "creates system group" do
      group = Group.new("app", system: true)

      assert group.system == true
    end

    test "creates non-system group explicitly" do
      group = Group.new("users", system: false)

      assert group.system == false
    end

    test "creates group with notify option" do
      group = Group.new("docker", notify: :restart_docker)

      assert group.notify == :restart_docker
    end

    test "creates group with when condition" do
      condition = {:==, :os, :linux}
      group = Group.new("docker", when: condition)

      assert group.when == condition
    end

    test "creates group with all options" do
      group =
        Group.new("developers",
          state: :present,
          gid: 1001,
          system: false,
          notify: :update_permissions,
          when: {:==, :os, :linux}
        )

      assert group.name == "developers"
      assert group.state == :present
      assert group.gid == 1001
      assert group.system == false
      assert group.notify == :update_permissions
      assert group.when == {:==, :os, :linux}
    end

    test "creates system group with gid" do
      group = Group.new("app", gid: 999, system: true)

      assert group.gid == 999
      assert group.system == true
    end
  end

  describe "describe/1" do
    test "describes group without gid" do
      group = Group.new("developers")
      desc = Group.describe(group)

      assert desc == "group[developers] state=present"
    end

    test "describes group with gid" do
      group = Group.new("developers", gid: 1001)
      desc = Group.describe(group)

      assert desc =~ "group[developers]"
      assert desc =~ "state=present"
    end

    test "describes group with absent state" do
      group = Group.new("oldgroup", state: :absent)
      desc = Group.describe(group)

      assert desc == "group[oldgroup] state=absent"
    end

    test "describes group with gid 0" do
      group = Group.new("root", gid: 0)
      desc = Group.describe(group)

      assert desc =~ "group[root]"
      assert desc =~ "state=present"
    end
  end

  describe "struct" do
    test "enforces :name as required key" do
      assert_raise ArgumentError, fn ->
        struct!(Group, [])
      end
    end

    test "has correct default values" do
      group = struct!(Group, name: "test")

      assert group.state == :present
      assert group.system == false
      assert group.when == true
      assert group.gid == nil
    end
  end
end

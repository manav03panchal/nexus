defmodule Nexus.Resources.Types.ServiceTest do
  use ExUnit.Case, async: true

  alias Nexus.Resources.Types.Service

  describe "new/1" do
    test "creates service with just name and defaults" do
      svc = Service.new("nginx")

      assert svc.name == "nginx"
      assert svc.state == nil
      assert svc.enabled == nil
      assert svc.action == nil
      assert svc.notify == nil
      assert svc.when == true
    end
  end

  describe "new/2" do
    test "creates service with :running state" do
      svc = Service.new("nginx", state: :running)

      assert svc.state == :running
    end

    test "creates service with :stopped state" do
      svc = Service.new("nginx", state: :stopped)

      assert svc.state == :stopped
    end

    test "creates service with :restarted state" do
      svc = Service.new("nginx", state: :restarted)

      assert svc.state == :restarted
    end

    test "creates service with :reloaded state" do
      svc = Service.new("nginx", state: :reloaded)

      assert svc.state == :reloaded
    end

    test "creates service with enabled true" do
      svc = Service.new("nginx", enabled: true)

      assert svc.enabled == true
    end

    test "creates service with enabled false" do
      svc = Service.new("nginx", enabled: false)

      assert svc.enabled == false
    end

    test "creates service with :start action" do
      svc = Service.new("nginx", action: :start)

      assert svc.action == :start
    end

    test "creates service with :stop action" do
      svc = Service.new("nginx", action: :stop)

      assert svc.action == :stop
    end

    test "creates service with :restart action" do
      svc = Service.new("nginx", action: :restart)

      assert svc.action == :restart
    end

    test "creates service with :reload action" do
      svc = Service.new("nginx", action: :reload)

      assert svc.action == :reload
    end

    test "creates service with :enable action" do
      svc = Service.new("nginx", action: :enable)

      assert svc.action == :enable
    end

    test "creates service with :disable action" do
      svc = Service.new("nginx", action: :disable)

      assert svc.action == :disable
    end

    test "creates service with notify option" do
      svc = Service.new("nginx", notify: :update_config)

      assert svc.notify == :update_config
    end

    test "creates service with when condition" do
      condition = {:==, :os, :linux}
      svc = Service.new("nginx", when: condition)

      assert svc.when == condition
    end

    test "creates service with all options" do
      svc =
        Service.new("nginx",
          state: :running,
          enabled: true,
          action: :restart,
          notify: :log_restart,
          when: {:==, :init_system, :systemd}
        )

      assert svc.name == "nginx"
      assert svc.state == :running
      assert svc.enabled == true
      assert svc.action == :restart
      assert svc.notify == :log_restart
      assert svc.when == {:==, :init_system, :systemd}
    end

    test "creates service running and enabled at boot" do
      svc = Service.new("nginx", state: :running, enabled: true)

      assert svc.state == :running
      assert svc.enabled == true
    end

    test "creates service stopped and disabled" do
      svc = Service.new("nginx", state: :stopped, enabled: false)

      assert svc.state == :stopped
      assert svc.enabled == false
    end
  end

  describe "describe/1" do
    test "describes service with just name" do
      svc = Service.new("nginx")
      desc = Service.describe(svc)

      assert desc == "service[nginx]"
    end

    test "describes service with state" do
      svc = Service.new("nginx", state: :running)
      desc = Service.describe(svc)

      assert desc =~ "service[nginx]"
      assert desc =~ "state=running"
    end

    test "describes service with enabled" do
      svc = Service.new("nginx", enabled: true)
      desc = Service.describe(svc)

      assert desc =~ "service[nginx]"
      assert desc =~ "enabled=true"
    end

    test "describes service with action" do
      svc = Service.new("nginx", action: :restart)
      desc = Service.describe(svc)

      assert desc =~ "service[nginx]"
      assert desc =~ "action=restart"
    end
  end

  describe "struct" do
    test "enforces :name as required key" do
      assert_raise ArgumentError, fn ->
        struct!(Service, [])
      end
    end

    test "has correct default values" do
      svc = struct!(Service, name: "test")

      assert svc.state == nil
      assert svc.enabled == nil
      assert svc.action == nil
      assert svc.notify == nil
      assert svc.when == true
    end
  end
end

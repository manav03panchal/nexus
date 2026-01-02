defmodule Nexus.Types.TemplateTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.Template

  describe "new/3" do
    test "creates template with required fields" do
      template = Template.new("templates/app.conf.eex", "/etc/app/config")

      assert template.source == "templates/app.conf.eex"
      assert template.destination == "/etc/app/config"
      assert template.vars == %{}
      assert template.sudo == false
      assert template.mode == nil
      assert template.notify == nil
    end

    test "creates template with vars option" do
      template =
        Template.new("app.conf.eex", "/etc/app/config", vars: %{port: 8080, env: "production"})

      assert template.vars == %{port: 8080, env: "production"}
    end

    test "creates template with sudo option" do
      template = Template.new("nginx.conf.eex", "/etc/nginx/nginx.conf", sudo: true)

      assert template.sudo == true
    end

    test "creates template with mode option" do
      template = Template.new("script.sh.eex", "/opt/app/script.sh", mode: 0o755)

      assert template.mode == 0o755
    end

    test "creates template with notify option" do
      template = Template.new("nginx.conf.eex", "/etc/nginx/nginx.conf", notify: :restart_nginx)

      assert template.notify == :restart_nginx
    end

    test "creates template with all options" do
      template =
        Template.new("app.conf.eex", "/etc/app/config",
          vars: %{port: 8080},
          sudo: true,
          mode: 0o644,
          notify: :reload_config
        )

      assert template.source == "app.conf.eex"
      assert template.destination == "/etc/app/config"
      assert template.vars == %{port: 8080}
      assert template.sudo == true
      assert template.mode == 0o644
      assert template.notify == :reload_config
    end
  end

  describe "struct" do
    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Template, [])
      end
    end
  end
end

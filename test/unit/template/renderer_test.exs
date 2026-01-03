defmodule Nexus.Template.RendererTest do
  use ExUnit.Case, async: true

  alias Nexus.Template.Renderer

  describe "render_string/2" do
    test "renders simple string without variables" do
      assert {:ok, "Hello, World!"} = Renderer.render_string("Hello, World!")
    end

    test "renders string with variable substitution" do
      template = "Hello, <%= @name %>!"
      vars = %{name: "Alice"}

      assert {:ok, "Hello, Alice!"} = Renderer.render_string(template, vars)
    end

    test "renders string with multiple variables" do
      template = "Server: <%= @host %>:<%= @port %>"
      vars = %{host: "localhost", port: 8080}

      assert {:ok, "Server: localhost:8080"} = Renderer.render_string(template, vars)
    end

    test "renders string with string keys in vars" do
      template = "Hello, <%= @name %>!"
      vars = %{"name" => "Bob"}

      assert {:ok, "Hello, Bob!"} = Renderer.render_string(template, vars)
    end

    test "renders string with complex expressions" do
      template = "Items: <%= Enum.join(@items, \", \") %>"
      vars = %{items: ["apple", "banana", "cherry"]}

      assert {:ok, "Items: apple, banana, cherry"} = Renderer.render_string(template, vars)
    end

    test "renders string with conditionals" do
      template = "<%= if @enabled, do: \"ON\", else: \"OFF\" %>"

      assert {:ok, "ON"} = Renderer.render_string(template, %{enabled: true})
      assert {:ok, "OFF"} = Renderer.render_string(template, %{enabled: false})
    end

    test "returns error for syntax errors" do
      template = "<%= @name"

      assert {:error, {:template_syntax_error, _}} =
               Renderer.render_string(template, %{name: "test"})
    end

    test "handles missing variables with empty string (EEx behavior)" do
      # Note: EEx returns empty string for missing assigns with a warning
      template = "<%= @missing_var %>"

      # Capture the expected warning about missing assign
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        send(self(), Renderer.render_string(template, %{}))
      end)

      assert_receive {:ok, ""}
    end
  end

  describe "render_file/2" do
    setup do
      # Create a temp directory for test templates
      tmp_dir =
        System.tmp_dir!()
        |> Path.join("nexus_renderer_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "renders template from file", %{tmp_dir: tmp_dir} do
      template_path = Path.join(tmp_dir, "test.eex")
      File.write!(template_path, "Hello, <%= @name %>!")

      assert {:ok, "Hello, World!"} = Renderer.render_file(template_path, %{name: "World"})
    end

    test "renders template with no variables", %{tmp_dir: tmp_dir} do
      template_path = Path.join(tmp_dir, "static.eex")
      File.write!(template_path, "Static content")

      assert {:ok, "Static content"} = Renderer.render_file(template_path)
    end

    test "returns error for non-existent file" do
      assert {:error, {:template_file_error, "/nonexistent/template.eex", :enoent}} =
               Renderer.render_file("/nonexistent/template.eex")
    end
  end

  describe "template_exists?/1" do
    setup do
      tmp_dir =
        System.tmp_dir!()
        |> Path.join("nexus_renderer_exists_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "returns true for existing file", %{tmp_dir: tmp_dir} do
      template_path = Path.join(tmp_dir, "exists.eex")
      File.write!(template_path, "content")

      assert Renderer.template_exists?(template_path)
    end

    test "returns false for non-existent file" do
      refute Renderer.template_exists?("/nonexistent/file.eex")
    end
  end
end

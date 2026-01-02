defmodule Nexus.Property.TemplatePropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Nexus.Template.Renderer
  alias Nexus.Types.Template

  @moduletag :property

  # Helper to ensure variable names start with lowercase (valid Elixir identifiers)
  defp valid_var_name?(atom) do
    name = Atom.to_string(atom)

    String.match?(name, ~r/^[a-z][a-z0-9_]*$/i) and
      String.downcase(String.first(name)) == String.first(name)
  end

  describe "Template struct properties" do
    property "preserves source path" do
      check all(source <- string(:printable, min_length: 1)) do
        template = Template.new(source, "/dest")
        assert template.source == source
      end
    end

    property "preserves destination path" do
      check all(destination <- string(:printable, min_length: 1)) do
        template = Template.new("/source", destination)
        assert template.destination == destination
      end
    end

    property "vars map is preserved" do
      check all(
              key <- atom(:alphanumeric),
              value <- one_of([string(:printable), integer(), boolean()])
            ) do
        vars = %{key => value}
        template = Template.new("/source", "/dest", vars: vars)
        assert template.vars == vars
      end
    end

    property "sudo option is boolean" do
      check all(sudo <- boolean()) do
        template = Template.new("/source", "/dest", sudo: sudo)
        assert template.sudo == sudo
      end
    end

    property "mode option preserves permissions" do
      check all(mode <- integer(0..0o777)) do
        template = Template.new("/source", "/dest", mode: mode)
        assert template.mode == mode
      end
    end

    property "notify option preserves handler reference" do
      check all(handler <- atom(:alphanumeric)) do
        template = Template.new("/source", "/dest", notify: handler)
        assert template.notify == handler
      end
    end
  end

  describe "Renderer properties" do
    property "static content is preserved" do
      check all(content <- string(:printable, max_length: 500)) do
        # Filter out EEx-like sequences that would be interpreted
        unless String.contains?(content, ["<%", "%>"]) do
          {:ok, result} = Renderer.render_string(content, %{})
          assert result == content
        end
      end
    end

    property "string variable substitution works" do
      check all(
              var_name <- atom(:alphanumeric) |> filter(&valid_var_name?/1),
              var_value <- string(:printable, max_length: 100)
            ) do
        # Filter out problematic characters
        unless String.contains?(var_value, ["<%", "%>", "<", ">"]) do
          template = "<%= @#{var_name} %>"
          {:ok, result} = Renderer.render_string(template, %{var_name => var_value})
          assert result == var_value
        end
      end
    end

    property "integer variable substitution works" do
      check all(
              var_name <- atom(:alphanumeric) |> filter(&valid_var_name?/1),
              var_value <- integer()
            ) do
        template = "<%= @#{var_name} %>"
        {:ok, result} = Renderer.render_string(template, %{var_name => var_value})
        assert result == Integer.to_string(var_value)
      end
    end

    property "boolean variable substitution works" do
      check all(
              var_name <- atom(:alphanumeric) |> filter(&valid_var_name?/1),
              var_value <- boolean()
            ) do
        template = "<%= @#{var_name} %>"
        {:ok, result} = Renderer.render_string(template, %{var_name => var_value})
        assert result == Atom.to_string(var_value)
      end
    end

    property "multiple variables are substituted correctly" do
      check all(
              val1 <- integer(0..1000),
              val2 <- integer(0..1000)
            ) do
        template = "a=<%= @a %>,b=<%= @b %>"
        {:ok, result} = Renderer.render_string(template, %{a: val1, b: val2})
        assert result == "a=#{val1},b=#{val2}"
      end
    end

    property "nested map access works" do
      check all(
              key <- atom(:alphanumeric) |> filter(&valid_var_name?/1),
              value <- string(:alphanumeric, min_length: 1, max_length: 20)
            ) do
        template = "<%= @config.#{key} %>"
        vars = %{config: %{key => value}}
        {:ok, result} = Renderer.render_string(template, vars)
        assert result == value
      end
    end
  end

  describe "template idempotence" do
    property "rendering same template twice gives same result" do
      check all(value <- integer()) do
        template = "value=<%= @val %>"
        vars = %{val: value}
        {:ok, result1} = Renderer.render_string(template, vars)
        {:ok, result2} = Renderer.render_string(template, vars)
        assert result1 == result2
      end
    end
  end
end

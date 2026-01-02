defmodule Nexus.Template.RendererEdgeCasesTest do
  use ExUnit.Case, async: true

  alias Nexus.Template.Renderer

  @moduletag :unit

  describe "variable binding edge cases" do
    test "handles nil values" do
      template = "Value: <%= @value %>"
      {:ok, result} = Renderer.render_string(template, %{value: nil})
      assert result == "Value: "
    end

    test "handles boolean values" do
      template = "Enabled: <%= @enabled %>, Disabled: <%= @disabled %>"
      {:ok, result} = Renderer.render_string(template, %{enabled: true, disabled: false})
      assert result == "Enabled: true, Disabled: false"
    end

    test "handles integer values" do
      template = "Port: <%= @port %>"
      {:ok, result} = Renderer.render_string(template, %{port: 8080})
      assert result == "Port: 8080"
    end

    test "handles float values" do
      template = "Rate: <%= @rate %>"
      {:ok, result} = Renderer.render_string(template, %{rate: 3.14159})
      assert result == "Rate: 3.14159"
    end

    test "handles atom values" do
      template = "Status: <%= @status %>"
      {:ok, result} = Renderer.render_string(template, %{status: :active})
      assert result == "Status: active"
    end

    test "handles list values" do
      template = "Items: <%= inspect(@items) %>"
      {:ok, result} = Renderer.render_string(template, %{items: [1, 2, 3]})
      assert result == "Items: [1, 2, 3]"
    end

    test "handles map values" do
      template = "Config: <%= inspect(@config) %>"
      {:ok, result} = Renderer.render_string(template, %{config: %{a: 1, b: 2}})
      assert result =~ "a:"
      assert result =~ "b:"
    end

    test "handles nested access" do
      template = "Nested: <%= @config.database.host %>"
      vars = %{config: %{database: %{host: "localhost"}}}
      {:ok, result} = Renderer.render_string(template, vars)
      assert result == "Nested: localhost"
    end

    test "handles deeply nested structures" do
      template = "<%= @a.b.c.d.e.f %>"
      vars = %{a: %{b: %{c: %{d: %{e: %{f: "deep"}}}}}}
      {:ok, result} = Renderer.render_string(template, vars)
      assert result == "deep"
    end
  end

  describe "template syntax edge cases" do
    test "handles empty template" do
      {:ok, result} = Renderer.render_string("", %{})
      assert result == ""
    end

    test "handles template with only whitespace" do
      {:ok, result} = Renderer.render_string("   \n\t  ", %{})
      assert result == "   \n\t  "
    end

    test "handles template with no variables" do
      template = "Static content only"
      {:ok, result} = Renderer.render_string(template, %{})
      assert result == "Static content only"
    end

    test "handles multiple variables on same line" do
      template = "<%= @a %> <%= @b %> <%= @c %>"
      {:ok, result} = Renderer.render_string(template, %{a: "x", b: "y", c: "z"})
      assert result == "x y z"
    end

    test "handles adjacent variables without separator" do
      template = "<%= @a %><%= @b %><%= @c %>"
      {:ok, result} = Renderer.render_string(template, %{a: "x", b: "y", c: "z"})
      assert result == "xyz"
    end

    test "handles variable at start of template" do
      template = "<%= @start %>rest"
      {:ok, result} = Renderer.render_string(template, %{start: "BEGIN:"})
      assert result == "BEGIN:rest"
    end

    test "handles variable at end of template" do
      template = "start<%= @suffix %>"
      {:ok, result} = Renderer.render_string(template, %{suffix: ":END"})
      assert result == "start:END"
    end

    test "handles multiline templates" do
      template = """
      Line 1: <%= @line1 %>
      Line 2: <%= @line2 %>
      Line 3: <%= @line3 %>
      """

      {:ok, result} =
        Renderer.render_string(template, %{line1: "first", line2: "second", line3: "third"})

      assert result =~ "Line 1: first"
      assert result =~ "Line 2: second"
      assert result =~ "Line 3: third"
    end

    test "handles EEx comments" do
      template = "Before<%# This is a comment %>After"
      {:ok, result} = Renderer.render_string(template, %{})
      assert result == "BeforeAfter"
    end

    test "handles EEx quotation preservation tag" do
      template = "<%% This stays as EEx %%>"
      {:ok, result} = Renderer.render_string(template, %{})
      # EEx escaping: <%% becomes <% and %%> becomes %>
      assert result == "<% This stays as EEx %%>"
    end
  end

  describe "control flow edge cases" do
    test "handles if-else" do
      template = "<%= if @flag, do: \"yes\", else: \"no\" %>"
      {:ok, yes} = Renderer.render_string(template, %{flag: true})
      {:ok, no} = Renderer.render_string(template, %{flag: false})
      assert yes == "yes"
      assert no == "no"
    end

    test "handles for comprehension" do
      template = "<%= for i <- @items do %><%= i %><% end %>"
      {:ok, result} = Renderer.render_string(template, %{items: [1, 2, 3]})
      assert result == "123"
    end

    test "handles empty for comprehension" do
      template = "<%= for i <- @items do %><%= i %><% end %>"
      {:ok, result} = Renderer.render_string(template, %{items: []})
      assert result == ""
    end

    test "handles case statement" do
      template = """
      <%= case @status do %>
      <% :ok -> %>Success
      <% :error -> %>Failure
      <% _ -> %>Unknown
      <% end %>
      """

      {:ok, result} = Renderer.render_string(template, %{status: :ok})
      assert result =~ "Success"
    end

    test "handles cond statement" do
      template = """
      <%= cond do %>
      <% @val > 10 -> %>Large
      <% @val > 5 -> %>Medium
      <% true -> %>Small
      <% end %>
      """

      {:ok, result} = Renderer.render_string(template, %{val: 15})
      assert result =~ "Large"
    end
  end

  describe "special character handling" do
    test "handles HTML entities" do
      template = "HTML: <%= @html %>"
      {:ok, result} = Renderer.render_string(template, %{html: "<script>alert('xss')</script>"})
      # EEx doesn't auto-escape, raw output
      assert result == "HTML: <script>alert('xss')</script>"
    end

    test "handles Unicode content" do
      template = "Unicode: <%= @text %>"
      {:ok, result} = Renderer.render_string(template, %{text: "日本語 🎉 émojis"})
      assert result == "Unicode: 日本語 🎉 émojis"
    end

    test "handles newlines in variables" do
      template = "Multi: <%= @text %>"
      {:ok, result} = Renderer.render_string(template, %{text: "line1\nline2\nline3"})
      assert result == "Multi: line1\nline2\nline3"
    end

    test "handles tabs in variables" do
      template = "Tabbed: <%= @text %>"
      {:ok, result} = Renderer.render_string(template, %{text: "col1\tcol2\tcol3"})
      assert result == "Tabbed: col1\tcol2\tcol3"
    end

    test "handles backslashes" do
      template = "Path: <%= @path %>"
      {:ok, result} = Renderer.render_string(template, %{path: "C:\\Windows\\System32"})
      assert result == "Path: C:\\Windows\\System32"
    end

    test "handles quotes in variables" do
      template = ~s(Quote: <%= @text %>)
      {:ok, result} = Renderer.render_string(template, %{text: ~s("quoted" and 'single')})
      assert result == ~s(Quote: "quoted" and 'single')
    end
  end

  describe "error handling edge cases" do
    test "handles undefined variable gracefully" do
      template = "Value: <%= @undefined_var %>"
      result = Renderer.render_string(template, %{})
      # Should return error or warning, not crash
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles syntax error in template" do
      template = "Bad: <%= @var"
      result = Renderer.render_string(template, %{var: "test"})
      assert {:error, _} = result
    end

    test "handles invalid Elixir expression" do
      template = "<%= this is not valid elixir %>"
      result = Renderer.render_string(template, %{})
      assert {:error, _} = result
    end

    test "handles runtime error in template" do
      template = "<%= 1 / @divisor %>"
      result = Renderer.render_string(template, %{divisor: 0})
      assert {:error, _} = result
    end

    test "handles nil method call" do
      template = "<%= @value.upcase() %>"
      result = Renderer.render_string(template, %{value: nil})
      assert {:error, _} = result
    end

    test "handles wrong type operation" do
      template = "<%= @number + @string %>"
      result = Renderer.render_string(template, %{number: 5, string: "text"})
      assert {:error, _} = result
    end
  end

  describe "large template handling" do
    test "handles large template content" do
      # 100KB of static content with variables interspersed
      content = String.duplicate("X", 10_000)
      template = "#{content}<%= @var %>#{content}<%= @var %>#{content}"
      {:ok, result} = Renderer.render_string(template, %{var: "VALUE"})
      assert String.length(result) > 30_000
      assert result =~ "VALUE"
    end

    test "handles many variables" do
      vars = for i <- 1..100, into: %{}, do: {String.to_atom("var#{i}"), "value#{i}"}
      template = Enum.map_join(1..100, " ", fn i -> "<%= @var#{i} %>" end)
      {:ok, result} = Renderer.render_string(template, vars)
      assert result =~ "value1"
      assert result =~ "value100"
    end

    test "handles deeply nested loops" do
      template = """
      <%= for a <- @as do %>
        <%= for b <- @bs do %>
          <%= for c <- @cs do %>
            (<%= a %>,<%= b %>,<%= c %>)
          <% end %>
        <% end %>
      <% end %>
      """

      {:ok, result} = Renderer.render_string(template, %{as: [1, 2], bs: [1, 2], cs: [1, 2]})
      assert result =~ "(1,1,1)"
      assert result =~ "(2,2,2)"
    end
  end

  describe "whitespace handling" do
    test "preserves indentation" do
      template = """
          indented line
              more indented
      """

      {:ok, result} = Renderer.render_string(template, %{})
      assert result =~ "    indented"
      assert result =~ "        more"
    end

    test "EEx output is preserved" do
      template = "<%= @val %>\nNext line"
      {:ok, result} = Renderer.render_string(template, %{val: "test"})
      assert result =~ "test"
      assert result =~ "Next"
    end

    test "handles Windows line endings" do
      template = "Line1\r\n<%= @val %>\r\nLine3"
      {:ok, result} = Renderer.render_string(template, %{val: "middle"})
      assert result =~ "Line1"
      assert result =~ "middle"
      assert result =~ "Line3"
    end
  end

  describe "function calls in templates" do
    test "allows String functions" do
      template = "<%= String.upcase(@text) %>"
      {:ok, result} = Renderer.render_string(template, %{text: "hello"})
      assert result == "HELLO"
    end

    test "allows Enum functions" do
      template = "<%= Enum.join(@items, \", \") %>"
      {:ok, result} = Renderer.render_string(template, %{items: ["a", "b", "c"]})
      assert result == "a, b, c"
    end

    test "allows Integer functions" do
      template = "<%= Integer.to_string(@num, 16) %>"
      {:ok, result} = Renderer.render_string(template, %{num: 255})
      assert result == "FF"
    end

    test "allows anonymous functions" do
      template = "<%= Enum.map(@items, fn x -> x * 2 end) |> Enum.join(\",\") %>"
      {:ok, result} = Renderer.render_string(template, %{items: [1, 2, 3]})
      assert result == "2,4,6"
    end
  end
end

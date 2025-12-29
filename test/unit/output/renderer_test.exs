defmodule Nexus.Output.RendererTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Nexus.Output.Renderer

  describe "render/2" do
    test "renders message to stdout" do
      output =
        capture_io(fn ->
          Renderer.render("Hello, World!", color: false)
        end)

      assert output == "Hello, World!\n"
    end

    test "renders message without newline" do
      output =
        capture_io(fn ->
          Renderer.render("Hello", color: false, newline: false)
        end)

      assert output == "Hello"
    end

    test "renders empty string with newline" do
      output =
        capture_io(fn ->
          Renderer.render("", color: false)
        end)

      assert output == "\n"
    end

    test "strips ANSI codes when color is disabled" do
      message = IO.ANSI.green() <> "Green text" <> IO.ANSI.reset()

      output =
        capture_io(fn ->
          Renderer.render(message, color: false)
        end)

      assert output == "Green text\n"
      refute output =~ "\e["
    end

    test "preserves ANSI codes when color is enabled" do
      message = IO.ANSI.green() <> "Green text" <> IO.ANSI.reset()

      output =
        capture_io(fn ->
          Renderer.render(message, color: true)
        end)

      assert output =~ "\e["
    end

    test "renders to stderr" do
      output =
        capture_io(:stderr, fn ->
          Renderer.render("Error message", device: :stderr, color: false)
        end)

      assert output == "Error message\n"
    end
  end

  describe "render_styled/3" do
    test "applies success style" do
      output =
        capture_io(fn ->
          Renderer.render_styled("Success!", :success, color: true)
        end)

      assert output =~ IO.ANSI.green()
      assert output =~ "Success!"
      assert output =~ IO.ANSI.reset()
    end

    test "applies error style" do
      output =
        capture_io(fn ->
          Renderer.render_styled("Error!", :error, color: true)
        end)

      assert output =~ IO.ANSI.red()
      assert output =~ "Error!"
    end

    test "applies warning style" do
      output =
        capture_io(fn ->
          Renderer.render_styled("Warning!", :warning, color: true)
        end)

      assert output =~ IO.ANSI.yellow()
      assert output =~ "Warning!"
    end

    test "applies info style" do
      output =
        capture_io(fn ->
          Renderer.render_styled("Info!", :info, color: true)
        end)

      assert output =~ IO.ANSI.blue()
      assert output =~ "Info!"
    end

    test "applies dim style" do
      output =
        capture_io(fn ->
          Renderer.render_styled("Dim text", :dim, color: true)
        end)

      assert output =~ IO.ANSI.faint()
      assert output =~ "Dim text"
    end

    test "applies bold style" do
      output =
        capture_io(fn ->
          Renderer.render_styled("Bold text", :bold, color: true)
        end)

      assert output =~ IO.ANSI.bright()
      assert output =~ "Bold text"
    end

    test "renders without style when color is disabled" do
      output =
        capture_io(fn ->
          Renderer.render_styled("Plain text", :success, color: false)
        end)

      assert output == "Plain text\n"
      refute output =~ "\e["
    end
  end

  describe "success/2" do
    test "renders green success message" do
      output =
        capture_io(fn ->
          Renderer.success("Build passed", color: true)
        end)

      assert output =~ IO.ANSI.green()
      assert output =~ "Build passed"
    end
  end

  describe "error/2" do
    test "renders red error message to stderr" do
      output =
        capture_io(:stderr, fn ->
          Renderer.error("Build failed", color: true)
        end)

      assert output =~ IO.ANSI.red()
      assert output =~ "Build failed"
    end
  end

  describe "warning/2" do
    test "renders yellow warning message" do
      output =
        capture_io(fn ->
          Renderer.warning("Deprecated feature", color: true)
        end)

      assert output =~ IO.ANSI.yellow()
      assert output =~ "Deprecated feature"
    end
  end

  describe "info/2" do
    test "renders blue info message" do
      output =
        capture_io(fn ->
          Renderer.info("Processing files", color: true)
        end)

      assert output =~ IO.ANSI.blue()
      assert output =~ "Processing files"
    end
  end

  describe "dim/2" do
    test "renders dimmed message" do
      output =
        capture_io(fn ->
          Renderer.dim("Secondary info", color: true)
        end)

      assert output =~ IO.ANSI.faint()
      assert output =~ "Secondary info"
    end
  end

  describe "newline/1" do
    test "renders a blank line" do
      output =
        capture_io(fn ->
          Renderer.newline(color: false)
        end)

      assert output == "\n"
    end
  end

  describe "rule/1" do
    test "renders a horizontal rule with default settings" do
      output =
        capture_io(fn ->
          Renderer.rule(color: false)
        end)

      assert output == String.duplicate("=", 40) <> "\n"
    end

    test "renders rule with custom width" do
      output =
        capture_io(fn ->
          Renderer.rule(width: 20, color: false)
        end)

      assert output == String.duplicate("=", 20) <> "\n"
    end

    test "renders rule with custom character" do
      output =
        capture_io(fn ->
          Renderer.rule(char: "-", width: 10, color: false)
        end)

      assert output == String.duplicate("-", 10) <> "\n"
    end
  end

  describe "header/2" do
    test "renders section header with title and underline" do
      output =
        capture_io(fn ->
          Renderer.header("Configuration", color: false)
        end)

      lines = String.split(output, "\n")
      assert Enum.at(lines, 1) == "Configuration"
      assert Enum.at(lines, 2) =~ ~r/^-+$/
    end
  end

  describe "stream_line/2" do
    test "renders line with prefix" do
      output =
        capture_io(fn ->
          Renderer.stream_line("output text", color: false)
        end)

      assert output == "  | output text\n"
    end

    test "renders line with custom prefix" do
      output =
        capture_io(fn ->
          Renderer.stream_line("output text", prefix: ">>> ", color: false)
        end)

      assert output == ">>> output text\n"
    end

    test "applies dim style to prefix when color enabled" do
      output =
        capture_io(fn ->
          Renderer.stream_line("output text", color: true)
        end)

      assert output =~ IO.ANSI.faint()
      assert output =~ "output text"
    end
  end

  describe "status/3" do
    test "renders ok status" do
      output =
        capture_io(fn ->
          Renderer.status(:ok, "Task completed", color: false)
        end)

      assert output == "[ok] Task completed\n"
    end

    test "renders error status" do
      output =
        capture_io(fn ->
          Renderer.status(:error, "Task failed", color: false)
        end)

      assert output == "[FAILED] Task failed\n"
    end

    test "renders warning status" do
      output =
        capture_io(fn ->
          Renderer.status(:warning, "Check config", color: false)
        end)

      assert output == "[warn] Check config\n"
    end

    test "renders info status" do
      output =
        capture_io(fn ->
          Renderer.status(:info, "Processing", color: false)
        end)

      assert output == "[info] Processing\n"
    end

    test "renders skip status" do
      output =
        capture_io(fn ->
          Renderer.status(:skip, "Skipped task", color: false)
        end)

      assert output == "[skip] Skipped task\n"
    end

    test "renders running status" do
      output =
        capture_io(fn ->
          Renderer.status(:running, "In progress", color: false)
        end)

      assert output == "[...] In progress\n"
    end

    test "renders custom status" do
      output =
        capture_io(fn ->
          Renderer.status(:custom, "Custom message", color: false)
        end)

      assert output == "[custom] Custom message\n"
    end

    test "applies color to status indicator" do
      output =
        capture_io(fn ->
          Renderer.status(:ok, "Task completed", color: true)
        end)

      assert output =~ IO.ANSI.green()
      assert output =~ "[ok]"
      assert output =~ IO.ANSI.reset()
    end

    test "applies error color to failed status" do
      output =
        capture_io(fn ->
          Renderer.status(:error, "Task failed", color: true)
        end)

      assert output =~ IO.ANSI.red()
      assert output =~ "[FAILED]"
    end
  end

  describe "colors_enabled?/0" do
    test "returns boolean" do
      result = Renderer.colors_enabled?()
      assert is_boolean(result)
    end
  end
end

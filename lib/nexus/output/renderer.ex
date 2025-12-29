defmodule Nexus.Output.Renderer do
  @moduledoc """
  Renders formatted output to the terminal.

  Handles color output, respects NO_COLOR environment variable,
  and provides streaming output capabilities.
  """

  @type device :: :stdio | :stderr

  @doc """
  Renders a message to the terminal.

  ## Options

    * `:device` - Output device, `:stdio` (default) or `:stderr`
    * `:color` - Enable/disable colors (default: auto-detect)
    * `:newline` - Add trailing newline (default: true)

  """
  @spec render(String.t(), keyword()) :: :ok
  def render(message, opts \\ []) do
    device = Keyword.get(opts, :device, :stdio)
    newline = Keyword.get(opts, :newline, true)
    color_enabled = Keyword.get(opts, :color, colors_enabled?())

    output =
      if color_enabled do
        message
      else
        strip_ansi(message)
      end

    output = if newline, do: output <> "\n", else: output

    case device do
      :stdio -> IO.write(output)
      :stderr -> IO.write(:stderr, output)
    end

    :ok
  end

  @doc """
  Renders a message with a specific style.

  ## Styles

    * `:success` - Green text
    * `:error` - Red text
    * `:warning` - Yellow text
    * `:info` - Blue text
    * `:dim` - Dimmed text
    * `:bold` - Bold text

  """
  @spec render_styled(String.t(), atom(), keyword()) :: :ok
  def render_styled(message, style, opts \\ []) do
    styled_message = apply_style(message, style, Keyword.get(opts, :color, colors_enabled?()))
    render(styled_message, opts)
  end

  @doc """
  Renders a success message (green).
  """
  @spec success(String.t(), keyword()) :: :ok
  def success(message, opts \\ []) do
    render_styled(message, :success, opts)
  end

  @doc """
  Renders an error message to stderr (red).
  """
  @spec error(String.t(), keyword()) :: :ok
  def error(message, opts \\ []) do
    opts = Keyword.put(opts, :device, :stderr)
    render_styled(message, :error, opts)
  end

  @doc """
  Renders a warning message (yellow).
  """
  @spec warning(String.t(), keyword()) :: :ok
  def warning(message, opts \\ []) do
    render_styled(message, :warning, opts)
  end

  @doc """
  Renders an info message (blue).
  """
  @spec info(String.t(), keyword()) :: :ok
  def info(message, opts \\ []) do
    render_styled(message, :info, opts)
  end

  @doc """
  Renders dimmed text.
  """
  @spec dim(String.t(), keyword()) :: :ok
  def dim(message, opts \\ []) do
    render_styled(message, :dim, opts)
  end

  @doc """
  Renders a blank line.
  """
  @spec newline(keyword()) :: :ok
  def newline(opts \\ []) do
    render("", opts)
  end

  @doc """
  Renders a horizontal rule.
  """
  @spec rule(keyword()) :: :ok
  def rule(opts \\ []) do
    width = Keyword.get(opts, :width, 40)
    char = Keyword.get(opts, :char, "=")
    render(String.duplicate(char, width), opts)
  end

  @doc """
  Renders a section header.
  """
  @spec header(String.t(), keyword()) :: :ok
  def header(title, opts \\ []) do
    newline(opts)
    render_styled(title, :bold, opts)
    rule(Keyword.put(opts, :char, "-"))
  end

  @doc """
  Renders streaming output line by line.
  """
  @spec stream_line(String.t(), keyword()) :: :ok
  def stream_line(line, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "  | ")
    color_enabled = Keyword.get(opts, :color, colors_enabled?())

    styled_prefix =
      if color_enabled do
        apply_style(prefix, :dim, true)
      else
        prefix
      end

    render(styled_prefix <> line, opts)
  end

  @doc """
  Renders a status indicator with a message.
  """
  @spec status(atom(), String.t(), keyword()) :: :ok
  def status(status_type, message, opts \\ []) do
    color_enabled = Keyword.get(opts, :color, colors_enabled?())

    {indicator, style} =
      case status_type do
        :ok -> {"[ok]", :success}
        :error -> {"[FAILED]", :error}
        :warning -> {"[warn]", :warning}
        :info -> {"[info]", :info}
        :skip -> {"[skip]", :dim}
        :running -> {"[...]", :info}
        _ -> {"[#{status_type}]", :dim}
      end

    styled_indicator =
      if color_enabled do
        apply_style(indicator, style, true)
      else
        indicator
      end

    render("#{styled_indicator} #{message}", opts)
  end

  @doc """
  Checks if colors are enabled.

  Colors are disabled if:
  - NO_COLOR environment variable is set
  - TERM is "dumb"
  - Not running in a TTY

  """
  @spec colors_enabled?() :: boolean()
  def colors_enabled? do
    no_color = System.get_env("NO_COLOR")
    term = System.get_env("TERM")

    cond do
      no_color != nil -> false
      term == "dumb" -> false
      true -> IO.ANSI.enabled?()
    end
  end

  # Private helpers

  defp apply_style(message, style, color_enabled) do
    if color_enabled do
      ansi_code = style_to_ansi(style)
      "#{ansi_code}#{message}#{IO.ANSI.reset()}"
    else
      message
    end
  end

  defp style_to_ansi(:success), do: IO.ANSI.green()
  defp style_to_ansi(:error), do: IO.ANSI.red()
  defp style_to_ansi(:warning), do: IO.ANSI.yellow()
  defp style_to_ansi(:info), do: IO.ANSI.blue()
  defp style_to_ansi(:dim), do: IO.ANSI.faint()
  defp style_to_ansi(:bold), do: IO.ANSI.bright()
  defp style_to_ansi(_), do: ""

  defp strip_ansi(string) do
    # Remove ANSI escape sequences
    String.replace(string, ~r/\e\[[0-9;]*m/, "")
  end
end

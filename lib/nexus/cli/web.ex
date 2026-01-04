defmodule Nexus.CLI.Web do
  @moduledoc """
  CLI handler for the `nexus web` command.

  Starts the Phoenix web dashboard for interactive DAG visualization
  and task execution.
  """

  alias Nexus.DSL.Parser
  alias Nexus.Output.Renderer

  @doc """
  Execute the web dashboard command.
  """
  def execute(parsed) do
    config_file = parsed.options[:config]
    port = parsed.options[:port]
    host = parse_host(parsed.options[:host])
    open_browser = parsed.flags[:open]

    # Validate config file exists
    config_path = Path.expand(config_file)

    if File.exists?(config_path) do
      # Validate the config parses correctly
      case Parser.parse_file(config_path) do
        {:ok, _config} ->
          start_dashboard(config_path, host, port, open_browser)

        {:error, reason} ->
          Renderer.error("Failed to parse config: #{inspect(reason)}")
          {:error, 1}
      end
    else
      Renderer.error("Config file not found: #{config_file}")
      {:error, 1}
    end
  end

  defp parse_host(host_string) do
    case String.split(host_string, ".") do
      [a, b, c, d] ->
        {String.to_integer(a), String.to_integer(b), String.to_integer(c), String.to_integer(d)}

      _ ->
        {127, 0, 0, 1}
    end
  end

  defp start_dashboard(config_path, host, port, open_browser) do
    IO.puts("")
    IO.puts("  ┌────────────────────────────────────────────────────┐")
    IO.puts("  │                                                    │")
    IO.puts("  │   Nexus Web Dashboard                              │")
    IO.puts("  │                                                    │")
    IO.puts("  │   Config: #{String.pad_trailing(Path.basename(config_path), 39)}│")

    IO.puts(
      "  │   URL:    http://#{format_host(host)}:#{port}#{String.duplicate(" ", 36 - String.length("#{format_host(host)}:#{port}"))}│"
    )

    IO.puts("  │                                                    │")
    IO.puts("  │   Press Ctrl+C twice to stop                       │")
    IO.puts("  │                                                    │")
    IO.puts("  └────────────────────────────────────────────────────┘")
    IO.puts("")

    # Start the web application
    case NexusWeb.Application.start_link(
           config_file: config_path,
           host: host,
           port: port
         ) do
      {:ok, _pid} ->
        if open_browser do
          open_browser_url("http://#{format_host(host)}:#{port}")
        end

        # Block forever (until Ctrl+C)
        Process.sleep(:infinity)

      {:error, reason} ->
        Renderer.error("Failed to start web dashboard: #{inspect(reason)}")
        {:error, 1}
    end
  end

  defp format_host({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp open_browser_url(url) do
    cmd =
      case :os.type() do
        {:unix, :darwin} -> "open"
        {:unix, _} -> "xdg-open"
        {:win32, _} -> "start"
      end

    System.cmd(cmd, [url], stderr_to_stdout: true)
  end
end

defmodule Nexus.Resources.DiffFormatter do
  @moduledoc """
  Formats resource execution results in diff-style output.

  Provides visual feedback showing what changed during resource execution,
  similar to Ansible's output format.

  ## Output Format

      [ok] package[nginx]
      [changed] file[/etc/nginx/nginx.conf]
               * content changed
               - checksum: abc123
               + checksum: def456
      [changed] service[nginx]
               * started service
               - running: false
               + running: true
      [skipped] user[deploy] (condition not met)
      [failed] command[mix deps.get]
               ! exit code 1: missing dependency

  """

  alias Nexus.Resources.Result

  @colors %{
    ok: :green,
    changed: :yellow,
    skipped: :cyan,
    failed: :red
  }

  @symbols %{
    ok: "✓",
    changed: "↻",
    skipped: "○",
    failed: "✗"
  }

  @doc """
  Formats a single resource result for display.
  """
  @spec format(Result.t(), keyword()) :: String.t()
  def format(%Result{} = result, opts \\ []) do
    color = Keyword.get(opts, :color, true)
    verbose = Keyword.get(opts, :verbose, false)

    status_line = format_status_line(result, color)
    details = format_details(result, verbose)

    if details == "" do
      status_line
    else
      status_line <> "\n" <> details
    end
  end

  @doc """
  Formats a list of resource results for display.
  """
  @spec format_all([Result.t()], keyword()) :: String.t()
  def format_all(results, opts \\ []) when is_list(results) do
    Enum.map_join(results, "\n", &format(&1, opts))
  end

  @doc """
  Formats a summary of all results.
  """
  @spec format_summary([Result.t()], keyword()) :: String.t()
  def format_summary(results, opts \\ []) when is_list(results) do
    color = Keyword.get(opts, :color, true)

    counts = count_by_status(results)
    total = length(results)
    duration_ms = Enum.sum(Enum.map(results, & &1.duration_ms))

    summary_parts = [
      "Resources: #{total} total",
      format_count("changed", counts.changed, :yellow, color),
      format_count("ok", counts.ok, :green, color),
      format_count("skipped", counts.skipped, :cyan, color),
      format_count("failed", counts.failed, :red, color)
    ]

    duration_str = format_duration(duration_ms)

    """
    ========================================
    #{Enum.join(summary_parts, ", ")}
    Duration: #{duration_str}
    """
  end

  @doc """
  Formats results grouped by host.
  """
  @spec format_by_host(map(), keyword()) :: String.t()
  def format_by_host(host_results, opts \\ []) when is_map(host_results) do
    Enum.map_join(host_results, "\n", fn {host, results} ->
      header = "\n  Host: #{host}\n"
      formatted = format_all(results, Keyword.put(opts, :indent, 4))
      header <> formatted
    end)
  end

  # Private functions

  defp format_status_line(%Result{} = result, color) do
    status = result.status
    symbol = Map.get(@symbols, status, "?")
    status_color = Map.get(@colors, status, :default)

    status_text = "[#{status}]"
    resource_text = result.resource

    if color do
      colorize("  #{symbol} #{status_text}", status_color) <> " #{resource_text}"
    else
      "  #{symbol} #{status_text} #{resource_text}"
    end
  end

  defp format_details(%Result{status: :ok}, _verbose), do: ""

  defp format_details(%Result{status: :skipped, message: msg}, _verbose) when not is_nil(msg) do
    "         (#{msg})"
  end

  defp format_details(%Result{status: :skipped}, _verbose), do: ""

  defp format_details(%Result{status: :failed, message: msg}, _verbose) when not is_nil(msg) do
    "         ! #{msg}"
  end

  defp format_details(%Result{status: :changed, diff: nil}, _verbose), do: ""

  defp format_details(%Result{status: :changed, diff: diff}, verbose) do
    format_diff(diff, verbose)
  end

  defp format_details(_, _), do: ""

  defp format_diff(nil, _), do: ""

  defp format_diff(%{changes: changes} = diff, verbose) when is_list(changes) do
    change_lines = Enum.map_join(changes, "\n", fn change -> "         * #{change}" end)

    if verbose and Map.has_key?(diff, :before) and Map.has_key?(diff, :after) do
      before_after = format_before_after(diff.before, diff.after)
      change_lines <> "\n" <> before_after
    else
      change_lines
    end
  end

  defp format_diff(diff, _verbose) when is_map(diff) do
    # Simple diff without changes list
    if Map.has_key?(diff, :action) do
      "         * #{diff.action}"
    else
      ""
    end
  end

  defp format_before_after(before_state, after_state)
       when is_map(before_state) and is_map(after_state) do
    # Find keys that changed
    all_keys =
      MapSet.union(MapSet.new(Map.keys(before_state)), MapSet.new(Map.keys(after_state)))

    all_keys
    |> Enum.filter(fn key ->
      Map.get(before_state, key) != Map.get(after_state, key)
    end)
    |> Enum.flat_map(fn key ->
      before_val = Map.get(before_state, key)
      after_val = Map.get(after_state, key)

      [
        "         - #{key}: #{inspect(before_val)}",
        "         + #{key}: #{inspect(after_val)}"
      ]
    end)
    |> Enum.join("\n")
  end

  defp format_before_after(_, _), do: ""

  defp count_by_status(results) do
    Enum.reduce(results, %{ok: 0, changed: 0, skipped: 0, failed: 0}, fn result, acc ->
      Map.update(acc, result.status, 1, &(&1 + 1))
    end)
  end

  defp format_count(_label, 0, _color, _use_color), do: nil

  defp format_count(label, count, color, true) do
    colorize("#{count} #{label}", color)
  end

  defp format_count(label, count, _color, false) do
    "#{count} #{label}"
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"

  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = rem(ms, 60_000) / 1000
    "#{minutes}m #{Float.round(seconds, 1)}s"
  end

  defp colorize(text, color) do
    IO.ANSI.format([color, text, :reset]) |> IO.iodata_to_binary()
  end
end

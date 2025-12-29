defmodule Nexus.CLI.Preflight do
  @moduledoc """
  CLI handler for the preflight command.

  Runs pre-flight checks to validate configuration, host connectivity,
  and SSH authentication before executing tasks.
  """

  alias Nexus.Output.Renderer
  alias Nexus.Preflight.Checker

  @doc """
  Executes the preflight command with the given parsed options.
  """
  @spec execute(map()) :: {:ok, integer()} | {:error, integer()}
  def execute(parsed) do
    config_path = parsed.options[:config]
    task_names = parse_tasks(parsed.args[:tasks])
    format = parsed.options[:format] || :text
    plain = parsed.flags[:plain] || false
    skip_checks = parse_skip_checks(parsed.options[:skip])
    verbose = parsed.flags[:verbose] || false

    opts = [
      config_path: config_path,
      tasks: task_names,
      skip_checks: skip_checks
    ]

    render_opts = [color: not plain]

    case Checker.run(opts) do
      {:ok, report} ->
        render_report(report, format, render_opts, verbose)
        {:ok, 0}

      {:error, report} ->
        render_report(report, format, render_opts, verbose)
        {:error, 1}
    end
  end

  defp parse_tasks(nil), do: []
  defp parse_tasks(""), do: []

  defp parse_tasks(tasks_str) do
    tasks_str
    |> String.split(~r/[\s,]+/, trim: true)
    |> Enum.map(&String.to_atom/1)
  end

  defp parse_skip_checks(nil), do: []

  defp parse_skip_checks(skip_str) do
    skip_str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_atom/1)
  end

  defp render_report(report, :json, _render_opts, _verbose) do
    output = %{
      status: report.status,
      duration_ms: report.duration_ms,
      checks:
        Enum.map(report.checks, fn check ->
          %{
            name: check.name,
            status: check.status,
            message: check.message
          }
        end),
      execution_plan: report.execution_plan
    }

    IO.puts(Jason.encode!(output, pretty: true))
  end

  defp render_report(report, :text, render_opts, verbose) do
    Renderer.newline(render_opts)
    Renderer.render_styled("Pre-flight Checks", :bold, render_opts)
    Renderer.rule(Keyword.put(render_opts, :char, "-"))

    Enum.each(report.checks, fn check ->
      render_check(check, render_opts, verbose)
    end)

    Renderer.newline(render_opts)

    if report.execution_plan && not Enum.empty?(report.execution_plan) do
      Renderer.render_styled("Execution Plan", :bold, render_opts)
      Renderer.rule(Keyword.put(render_opts, :char, "-"))
      Renderer.render(Checker.format_plan(report.execution_plan), render_opts)
      Renderer.newline(render_opts)
    end

    # Summary
    Renderer.rule(render_opts)

    case report.status do
      :ok ->
        Renderer.success("All checks passed (#{report.duration_ms}ms)", render_opts)

      :error ->
        failed_count = Enum.count(report.checks, fn c -> c.status == :failed end)
        Renderer.error("#{failed_count} check(s) failed (#{report.duration_ms}ms)", render_opts)
    end
  end

  defp render_check(check, render_opts, verbose) do
    status_type =
      case check.status do
        :passed -> :ok
        :failed -> :error
        :skipped -> :skip
      end

    Renderer.status(status_type, "#{check.name}: #{check.message}", render_opts)

    if verbose && check.details do
      render_check_details(check.name, check.details, render_opts)
    end
  end

  defp render_check_details(:config, %{tasks: t, hosts: h, groups: g}, render_opts) do
    Renderer.dim("     Tasks: #{t}, Hosts: #{h}, Groups: #{g}", render_opts)
  end

  defp render_check_details(:hosts, results, render_opts) when is_list(results) do
    Enum.each(results, fn {name, status, reason} ->
      case status do
        :reachable ->
          Renderer.dim("     #{name}: reachable", render_opts)

        :unreachable ->
          Renderer.dim("     #{name}: unreachable (#{inspect(reason)})", render_opts)
      end
    end)
  end

  defp render_check_details(:ssh, results, render_opts) when is_list(results) do
    Enum.each(results, fn {name, status, reason} ->
      case status do
        :ok ->
          Renderer.dim("     #{name}: authenticated", render_opts)

        :failed ->
          Renderer.dim("     #{name}: failed (#{inspect(reason)})", render_opts)
      end
    end)
  end

  defp render_check_details(:tasks, tasks, render_opts) when is_list(tasks) do
    Renderer.dim(
      "     Available: #{Enum.map_join(tasks, ", ", &Atom.to_string/1)}",
      render_opts
    )
  end

  defp render_check_details(:tasks, %{unknown: unknown}, render_opts) do
    Renderer.dim(
      "     Unknown: #{Enum.map_join(unknown, ", ", &Atom.to_string/1)}",
      render_opts
    )
  end

  defp render_check_details(_name, _details, _render_opts), do: :ok
end

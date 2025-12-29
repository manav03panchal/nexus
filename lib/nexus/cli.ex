defmodule Nexus.CLI do
  @moduledoc """
  Command-line interface for Nexus.

  Provides the main entry point and command routing for the Nexus CLI.
  Uses Optimus for argument parsing.

  ## Commands

    * `run <task> [tasks...]` - Execute one or more tasks
    * `list` - List all defined tasks
    * `validate` - Validate the nexus.exs configuration
    * `init` - Create a template nexus.exs file
    * `version` - Show version information

  ## Examples

      $ nexus run deploy
      $ nexus run build test deploy
      $ nexus list
      $ nexus validate
      $ nexus run deploy --dry-run --verbose

  """

  alias Nexus.CLI.{Init, List, Preflight, Run, Validate}

  @version Mix.Project.config()[:version] || "0.1.0"

  @doc """
  Main entry point for the CLI.

  Parses command-line arguments and dispatches to the appropriate command handler.
  """
  @spec main([String.t()]) :: no_return()
  def main(args) do
    args
    |> parse()
    |> execute()
    |> exit_with_code()
  end

  @doc """
  Returns the Optimus configuration for CLI parsing.
  """
  def optimus_config do
    Optimus.new!(
      name: "nexus",
      description: "Distributed task runner with SSH support",
      version: @version,
      author: "Nexus Contributors",
      about: "Execute tasks locally or on remote hosts with dependency resolution.",
      allow_unknown_args: false,
      parse_double_dash: true,
      subcommands: [
        run: [
          name: "run",
          about: "Execute one or more tasks",
          args: [
            tasks: [
              value_name: "TASKS",
              help: "Tasks to execute",
              required: true,
              parser: :string
            ]
          ],
          options: [
            config: [
              value_name: "FILE",
              short: "-c",
              long: "--config",
              help: "Path to nexus.exs config file",
              parser: :string,
              default: "nexus.exs"
            ],
            identity: [
              value_name: "FILE",
              short: "-i",
              long: "--identity",
              help: "SSH private key file",
              parser: :string
            ],
            user: [
              value_name: "USER",
              short: "-u",
              long: "--user",
              help: "SSH user",
              parser: :string
            ],
            parallel_limit: [
              value_name: "N",
              short: "-p",
              long: "--parallel-limit",
              help: "Maximum parallel tasks",
              parser: :integer,
              default: 10
            ],
            format: [
              value_name: "FORMAT",
              long: "--format",
              help: "Output format (text, json)",
              parser: &parse_format/1,
              default: :text
            ]
          ],
          flags: [
            dry_run: [
              short: "-n",
              long: "--dry-run",
              help: "Show execution plan without running"
            ],
            verbose: [
              short: "-v",
              long: "--verbose",
              help: "Increase output verbosity"
            ],
            quiet: [
              short: "-q",
              long: "--quiet",
              help: "Minimal output"
            ],
            continue_on_error: [
              long: "--continue-on-error",
              help: "Continue executing on task failure"
            ],
            plain: [
              long: "--plain",
              help: "Disable colors and formatting"
            ]
          ]
        ],
        list: [
          name: "list",
          about: "List all defined tasks",
          options: [
            config: [
              value_name: "FILE",
              short: "-c",
              long: "--config",
              help: "Path to nexus.exs config file",
              parser: :string,
              default: "nexus.exs"
            ],
            format: [
              value_name: "FORMAT",
              long: "--format",
              help: "Output format (text, json)",
              parser: &parse_format/1,
              default: :text
            ]
          ],
          flags: [
            plain: [
              long: "--plain",
              help: "Disable colors and formatting"
            ]
          ]
        ],
        validate: [
          name: "validate",
          about: "Validate nexus.exs configuration",
          options: [
            config: [
              value_name: "FILE",
              short: "-c",
              long: "--config",
              help: "Path to nexus.exs config file",
              parser: :string,
              default: "nexus.exs"
            ]
          ]
        ],
        preflight: [
          name: "preflight",
          about: "Run pre-flight checks before execution",
          args: [
            tasks: [
              value_name: "TASKS",
              help: "Tasks to check (optional)",
              required: false,
              parser: :string
            ]
          ],
          options: [
            config: [
              value_name: "FILE",
              short: "-c",
              long: "--config",
              help: "Path to nexus.exs config file",
              parser: :string,
              default: "nexus.exs"
            ],
            skip: [
              value_name: "CHECKS",
              long: "--skip",
              help: "Checks to skip (comma-separated: config,hosts,ssh,tasks)",
              parser: :string
            ],
            format: [
              value_name: "FORMAT",
              long: "--format",
              help: "Output format (text, json)",
              parser: &parse_format/1,
              default: :text
            ]
          ],
          flags: [
            verbose: [
              short: "-v",
              long: "--verbose",
              help: "Show detailed check results"
            ],
            plain: [
              long: "--plain",
              help: "Disable colors and formatting"
            ]
          ]
        ],
        init: [
          name: "init",
          about: "Create a template nexus.exs file",
          options: [
            output: [
              value_name: "FILE",
              short: "-o",
              long: "--output",
              help: "Output file path",
              parser: :string,
              default: "nexus.exs"
            ]
          ],
          flags: [
            force: [
              short: "-f",
              long: "--force",
              help: "Overwrite existing file"
            ]
          ]
        ]
      ]
    )
  end

  defp parse(args) do
    Optimus.parse(optimus_config(), args)
  end

  # Parse error with subcommand context
  defp execute({:error, _subcommand, errors}) do
    IO.puts(:stderr, format_parse_errors(errors))
    {:error, 1}
  end

  # Parse error without subcommand
  defp execute({:error, errors}) do
    IO.puts(:stderr, format_parse_errors(errors))
    {:error, 1}
  end

  # Help/version was requested
  defp execute(:help) do
    {:ok, 0}
  end

  defp execute(:version) do
    {:ok, 0}
  end

  # No subcommand - show help
  defp execute({:ok, %{args: %{}, flags: %{}, options: %{}}}) do
    Optimus.parse!(optimus_config(), ["--help"])
    {:ok, 0}
  end

  # Subcommand execution
  defp execute({:ok, [:run], parsed}) do
    Run.execute(parsed)
  end

  defp execute({:ok, [:list], parsed}) do
    List.execute(parsed)
  end

  defp execute({:ok, [:validate], parsed}) do
    Validate.execute(parsed)
  end

  defp execute({:ok, [:init], parsed}) do
    Init.execute(parsed)
  end

  defp execute({:ok, [:preflight], parsed}) do
    Preflight.execute(parsed)
  end

  # System.halt/1 never returns, which is expected for CLI exit behavior
  @dialyzer {:nowarn_function, exit_with_code: 1}
  defp exit_with_code({:ok, code}), do: System.halt(code)
  defp exit_with_code({:error, code}), do: System.halt(code)

  defp format_parse_errors(errors) when is_list(errors) do
    Enum.map_join(errors, "\n", &format_parse_error/1)
  end

  defp format_parse_error(error) when is_binary(error) do
    "Error: #{error}"
  end

  defp format_parse_error({:undefined_command, cmd}) do
    "Error: Unknown command '#{cmd}'"
  end

  defp format_parse_error({:missing_argument, arg}) do
    "Error: Missing required argument: #{arg}"
  end

  defp format_parse_error({:invalid_option, opt, reason}) do
    "Error: Invalid option '#{opt}': #{reason}"
  end

  # Parser for format option (used by Optimus)
  @doc false
  def parse_format("text"), do: {:ok, :text}
  def parse_format("json"), do: {:ok, :json}
  def parse_format(_), do: {:error, "must be 'text' or 'json'"}
end

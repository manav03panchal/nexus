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

  alias Nexus.CLI.{Init, List, Preflight, Run, Secret, Validate}

  @version Mix.Project.config()[:version] || "0.1.0"

  @doc """
  Main entry point for the CLI.

  Parses command-line arguments and dispatches to the appropriate command handler.
  """
  @spec main([String.t()]) :: no_return()
  def main(args) do
    args
    |> maybe_convert_help()
    |> parse()
    |> execute()
    |> exit_with_code()
  end

  # Convert "subcommand --help" to "help subcommand"
  defp maybe_convert_help(args) do
    case args do
      [cmd, "--help"] -> ["help", cmd]
      [cmd, "-h"] -> ["help", cmd]
      _ -> args
    end
  end

  @doc """
  Returns the Optimus configuration for CLI parsing.
  """
  def optimus_config do
    Optimus.new!(
      name: "nexus",
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
            password: [
              value_name: "PASSWORD",
              long: "--password",
              help: "SSH password (use - for prompt)",
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
            ],
            tags: [
              value_name: "TAGS",
              short: "-t",
              long: "--tags",
              help: "Only run tasks with these tags (comma-separated)",
              parser: :string
            ],
            skip_tags: [
              value_name: "TAGS",
              long: "--skip-tags",
              help: "Skip tasks with these tags (comma-separated)",
              parser: :string
            ]
          ],
          flags: [
            dry_run: [
              short: "-n",
              long: "--dry-run",
              help: "Show execution plan without running"
            ],
            check: [
              long: "--check",
              help: "Preview changes without executing (shows diffs for templates)"
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
            ],
            insecure: [
              long: "--insecure",
              help: "Accept unknown SSH host keys without prompting (insecure)"
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
            identity: [
              value_name: "FILE",
              short: "-i",
              long: "--identity",
              help: "SSH private key file",
              parser: :string
            ],
            password: [
              value_name: "PASSWORD",
              long: "--password",
              help: "SSH password (use - for prompt)",
              parser: :string
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
            ],
            insecure: [
              long: "--insecure",
              help: "Accept unknown SSH host keys without prompting (insecure)"
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
        ],
        secret: [
          name: "secret",
          about: "Manage encrypted secrets",
          subcommands: [
            init: [
              name: "init",
              about: "Initialize the secrets vault with a new master key"
            ],
            set: [
              name: "set",
              about: "Set a secret value",
              args: [
                name: [
                  value_name: "NAME",
                  help: "Secret name",
                  required: true,
                  parser: :string
                ],
                value: [
                  value_name: "VALUE",
                  help: "Secret value (omit to prompt securely)",
                  required: false,
                  parser: :string
                ]
              ],
              flags: [
                force: [
                  short: "-f",
                  long: "--force",
                  help: "Overwrite existing secret"
                ]
              ]
            ],
            get: [
              name: "get",
              about: "Get a secret value",
              args: [
                name: [
                  value_name: "NAME",
                  help: "Secret name",
                  required: true,
                  parser: :string
                ]
              ]
            ],
            list: [
              name: "list",
              about: "List all secret names",
              options: [
                format: [
                  value_name: "FORMAT",
                  long: "--format",
                  help: "Output format (text, json)",
                  parser: &parse_format/1,
                  default: :text
                ]
              ]
            ],
            delete: [
              name: "delete",
              about: "Delete a secret",
              args: [
                name: [
                  value_name: "NAME",
                  help: "Secret name",
                  required: true,
                  parser: :string
                ]
              ]
            ]
          ]
        ],
        version: [
          name: "version",
          about: "Show Nexus version information"
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

  # Help was requested (top-level)
  defp execute(:help) do
    Optimus.parse!(optimus_config(), ["--help"])
    {:ok, 0}
  end

  defp execute(:version) do
    IO.puts("nexus #{@version}")
    {:ok, 0}
  end

  # Help was requested for a subcommand
  defp execute({:help, [subcommand_name]}) do
    config = optimus_config()
    subcmd = Enum.find(config.subcommands, &(&1.name == Atom.to_string(subcommand_name)))

    if subcmd do
      print_subcommand_help(subcmd)
    else
      IO.puts(:stderr, "Unknown command: #{subcommand_name}")
    end

    {:ok, 0}
  end

  defp execute({:help, _subcommand_path}) do
    # Nested subcommands not supported
    Optimus.parse!(optimus_config(), ["--help"])
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

  # Secret subcommands
  defp execute({:ok, [:secret, :init], parsed}) do
    Secret.execute_init(parsed)
  end

  defp execute({:ok, [:secret, :set], parsed}) do
    Secret.execute_set(parsed)
  end

  defp execute({:ok, [:secret, :get], parsed}) do
    Secret.execute_get(parsed)
  end

  defp execute({:ok, [:secret, :list], parsed}) do
    Secret.execute_list(parsed)
  end

  defp execute({:ok, [:secret, :delete], parsed}) do
    Secret.execute_delete(parsed)
  end

  defp execute({:ok, [:version], _parsed}) do
    IO.puts("nexus #{@version}")
    {:ok, 0}
  end

  defp print_subcommand_help(subcmd) do
    IO.puts(subcmd.about || subcmd.name)
    IO.puts("")
    print_usage(subcmd)
    print_args(subcmd.args)
    print_flags(subcmd.flags)
    print_options(subcmd.options)
    IO.puts("")
  end

  defp print_usage(subcmd) do
    flags_str = if Enum.any?(subcmd.flags), do: " [FLAGS]", else: ""
    opts_str = if Enum.any?(subcmd.options), do: " [OPTIONS]", else: ""

    args_str =
      Enum.map_join(subcmd.args, "", fn arg ->
        if arg.required, do: " #{arg.value_name}", else: " [#{arg.value_name}]"
      end)

    IO.puts("USAGE:")
    IO.puts("    nexus #{subcmd.name}#{flags_str}#{opts_str}#{args_str}")
  end

  defp print_args([]), do: :ok

  defp print_args(args) do
    IO.puts("")
    IO.puts("ARGS:")

    Enum.each(args, fn arg ->
      IO.puts("    #{String.pad_trailing(arg.value_name, 16)} #{arg.help || ""}")
    end)
  end

  defp print_flags([]), do: :ok

  defp print_flags(flags) do
    IO.puts("")
    IO.puts("FLAGS:")

    Enum.each(flags, fn flag ->
      short = if flag.short, do: "#{flag.short}, ", else: "    "
      long = flag.long || ""
      IO.puts("    #{short}#{String.pad_trailing(long, 24)} #{flag.help || ""}")
    end)
  end

  defp print_options([]), do: :ok

  defp print_options(options) do
    IO.puts("")
    IO.puts("OPTIONS:")

    Enum.each(options, fn opt ->
      short = if opt.short, do: "#{opt.short}, ", else: "    "
      long = opt.long || ""
      default = if opt.default, do: " (default: #{opt.default})", else: ""
      IO.puts("    #{short}#{String.pad_trailing(long, 24)} #{opt.help || ""}#{default}")
    end)
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

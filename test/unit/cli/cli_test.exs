defmodule Nexus.CLITest do
  use ExUnit.Case, async: true

  alias Nexus.CLI

  @moduletag :unit

  describe "optimus_config/0" do
    test "returns valid Optimus configuration" do
      config = CLI.optimus_config()

      assert config.name == "nexus"
      assert is_binary(config.description) or is_nil(config.description)
      assert is_binary(config.version)
    end

    test "defines run subcommand" do
      config = CLI.optimus_config()

      # Subcommands are a list in Optimus
      run = Enum.find(config.subcommands, &(&1.name == "run"))

      assert run != nil
      assert run.name == "run"

      # Args are a list
      tasks_arg = Enum.find(run.args, &(&1.name == :tasks))
      assert tasks_arg != nil

      # Options are a list
      option_names = Enum.map(run.options, & &1.name)
      assert :config in option_names
      assert :identity in option_names
      assert :user in option_names
      assert :parallel_limit in option_names
      assert :format in option_names

      # Flags are a list (dry_run, verbose, quiet, continue_on_error moved here)
      flag_names = Enum.map(run.flags, & &1.name)
      assert :dry_run in flag_names
      assert :verbose in flag_names
      assert :quiet in flag_names
      assert :continue_on_error in flag_names
      assert :plain in flag_names
    end

    test "defines list subcommand" do
      config = CLI.optimus_config()

      list = Enum.find(config.subcommands, &(&1.name == "list"))

      assert list != nil
      assert list.name == "list"

      option_names = Enum.map(list.options, & &1.name)
      assert :config in option_names
      assert :format in option_names
    end

    test "defines validate subcommand" do
      config = CLI.optimus_config()

      validate = Enum.find(config.subcommands, &(&1.name == "validate"))

      assert validate != nil
      assert validate.name == "validate"

      option_names = Enum.map(validate.options, & &1.name)
      assert :config in option_names
    end

    test "defines init subcommand" do
      config = CLI.optimus_config()

      init = Enum.find(config.subcommands, &(&1.name == "init"))

      assert init != nil
      assert init.name == "init"

      option_names = Enum.map(init.options, & &1.name)
      assert :output in option_names

      flag_names = Enum.map(init.flags, & &1.name)
      assert :force in flag_names
    end
  end

  describe "argument parsing" do
    test "parses run command with task" do
      config = CLI.optimus_config()

      {:ok, [:run], parsed} = Optimus.parse(config, ["run", "build"])

      assert parsed.args[:tasks] == "build"
      assert parsed.options[:config] == "nexus.exs"
    end

    test "parses run command with multiple tasks" do
      config = CLI.optimus_config()

      {:ok, [:run], parsed} = Optimus.parse(config, ["run", "build test deploy"])

      assert parsed.args[:tasks] == "build test deploy"
    end

    test "parses run command with flags" do
      config = CLI.optimus_config()

      # Note: --dry-run and --verbose are flags in Optimus, not boolean options
      {:ok, [:run], parsed} =
        Optimus.parse(config, ["run", "build", "-c", "custom.exs"])

      assert parsed.options[:config] == "custom.exs"
    end

    test "parses list command" do
      config = CLI.optimus_config()

      {:ok, [:list], parsed} = Optimus.parse(config, ["list"])

      assert parsed.options[:config] == "nexus.exs"
      assert parsed.options[:format] == :text
    end

    test "parses list command with json format" do
      config = CLI.optimus_config()

      {:ok, [:list], parsed} = Optimus.parse(config, ["list", "--format", "json"])

      assert parsed.options[:format] == :json
    end

    test "parses validate command" do
      config = CLI.optimus_config()

      {:ok, [:validate], parsed} = Optimus.parse(config, ["validate"])

      assert parsed.options[:config] == "nexus.exs"
    end

    test "parses validate command with custom config" do
      config = CLI.optimus_config()

      {:ok, [:validate], parsed} = Optimus.parse(config, ["validate", "-c", "prod.exs"])

      assert parsed.options[:config] == "prod.exs"
    end

    test "parses init command" do
      config = CLI.optimus_config()

      {:ok, [:init], parsed} = Optimus.parse(config, ["init"])

      assert parsed.options[:output] == "nexus.exs"
      assert parsed.flags[:force] == false
    end

    test "parses init command with force flag" do
      config = CLI.optimus_config()

      {:ok, [:init], parsed} = Optimus.parse(config, ["init", "--force", "-o", "custom.exs"])

      assert parsed.options[:output] == "custom.exs"
      assert parsed.flags[:force] == true
    end

    test "rejects invalid format option" do
      config = CLI.optimus_config()

      # Optimus returns {:error, subcommand_path, errors} for option errors
      {:error, [:run], _errors} = Optimus.parse(config, ["run", "build", "--format", "yaml"])
    end

    test "rejects unknown command" do
      config = CLI.optimus_config()

      {:error, _} = Optimus.parse(config, ["unknown"])
    end
  end

  describe "SSH options" do
    test "parses identity option" do
      config = CLI.optimus_config()

      {:ok, [:run], parsed} =
        Optimus.parse(config, ["run", "deploy", "-i", "~/.ssh/deploy_key"])

      assert parsed.options[:identity] == "~/.ssh/deploy_key"
    end

    test "parses user option" do
      config = CLI.optimus_config()

      {:ok, [:run], parsed} = Optimus.parse(config, ["run", "deploy", "-u", "deploy"])

      assert parsed.options[:user] == "deploy"
    end

    test "parses parallel limit option" do
      config = CLI.optimus_config()

      {:ok, [:run], parsed} = Optimus.parse(config, ["run", "deploy", "-p", "5"])

      assert parsed.options[:parallel_limit] == 5
    end
  end
end

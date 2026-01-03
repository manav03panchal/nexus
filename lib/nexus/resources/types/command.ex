defmodule Nexus.Resources.Types.Command do
  @moduledoc """
  Command resource - declarative replacement for `run`.

  Unlike the basic `run` command, the Command resource supports
  idempotency guards that prevent unnecessary execution:

  - `creates:` - Skip if this path exists
  - `removes:` - Skip if this path doesn't exist
  - `unless:` - Skip if this command succeeds
  - `onlyif:` - Only run if this command succeeds

  ## Examples

      # Always runs (like traditional run)
      command "echo hello"

      # Only runs if file doesn't exist (idempotent)
      command "tar -xzf app.tar.gz -C /opt/app",
        creates: "/opt/app/bin/app"

      # Only runs if file exists
      command "rm -rf /tmp/cache",
        removes: "/tmp/cache"

      # Only runs if check command fails (0 = skip)
      command "mix deps.get",
        unless: "mix deps.check",
        cwd: "/opt/app"

      # Only runs if check command succeeds (0 = run)
      command "systemctl restart app",
        onlyif: "systemctl is-active app"

      # With sudo
      command "systemctl restart nginx", sudo: true

      # With environment variables
      command "mix release",
        env: %{"MIX_ENV" => "prod"},
        cwd: "/opt/app"

      # With timeout
      command "long_running_script.sh", timeout: 300_000

      # With handler notification
      command "nginx -t", notify: :reload_nginx

  """

  @type condition :: term()

  @type t :: %__MODULE__{
          cmd: String.t(),
          creates: String.t() | nil,
          removes: String.t() | nil,
          unless: String.t() | nil,
          onlyif: String.t() | nil,
          sudo: boolean(),
          user: String.t() | nil,
          cwd: String.t() | nil,
          env: map(),
          timeout: pos_integer(),
          when: condition(),
          notify: atom() | nil
        }

  @enforce_keys [:cmd]
  defstruct [
    :cmd,
    :creates,
    :removes,
    :unless,
    :onlyif,
    :user,
    :cwd,
    :notify,
    sudo: false,
    env: %{},
    timeout: 60_000,
    when: true
  ]

  @doc """
  Creates a new Command resource.

  ## Options

    * `:creates` - Path that should exist after command runs (skip if exists)
    * `:removes` - Path that should not exist after command runs (skip if absent)
    * `:unless` - Command that must fail for this command to run
    * `:onlyif` - Command that must succeed for this command to run
    * `:sudo` - Run with sudo. Default `false`.
    * `:user` - Run as specific user (with sudo)
    * `:cwd` - Working directory for command
    * `:env` - Environment variables map
    * `:timeout` - Command timeout in ms. Default `60_000`.
    * `:notify` - Handler to trigger on change
    * `:when` - Condition for execution

  """
  @spec new(String.t(), keyword()) :: t()
  def new(cmd, opts \\ []) do
    %__MODULE__{
      cmd: cmd,
      creates: Keyword.get(opts, :creates),
      removes: Keyword.get(opts, :removes),
      unless: Keyword.get(opts, :unless),
      onlyif: Keyword.get(opts, :onlyif),
      sudo: Keyword.get(opts, :sudo, false),
      user: Keyword.get(opts, :user),
      cwd: Keyword.get(opts, :cwd),
      env: Keyword.get(opts, :env, %{}),
      timeout: Keyword.get(opts, :timeout, 60_000),
      notify: Keyword.get(opts, :notify),
      when: Keyword.get(opts, :when, true)
    }
  end

  @doc """
  Returns a human-readable description of the resource.
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{cmd: cmd}) do
    preview =
      if String.length(cmd) > 50 do
        String.slice(cmd, 0, 47) <> "..."
      else
        cmd
      end

    "command[#{preview}]"
  end

  @doc """
  Checks if this command has any idempotency guards.
  """
  @spec idempotent?(t()) :: boolean()
  def idempotent?(%__MODULE__{creates: c, removes: r, unless: u, onlyif: o}) do
    c != nil or r != nil or u != nil or o != nil
  end
end

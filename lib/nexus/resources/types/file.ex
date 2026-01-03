defmodule Nexus.Resources.Types.File do
  @moduledoc """
  File resource for managing files on remote hosts.

  Supports:
  - Creating files from templates (EEx)
  - Creating files from local source
  - Creating files from inline content
  - Setting ownership and permissions
  - Removing files

  ## Examples

      # From template
      file "/etc/nginx/nginx.conf",
        source: "templates/nginx.conf.eex",
        vars: %{port: 8080, workers: 4},
        owner: "root",
        group: "root",
        mode: 0o644

      # From local file
      file "/etc/app/config.json",
        source: "configs/app.json",
        owner: "app",
        mode: 0o600

      # From inline content
      file "/etc/motd",
        content: "Welcome to the server!",
        mode: 0o644

      # Remove file
      file "/tmp/old_file", state: :absent

      # With handler notification
      file "/etc/nginx/nginx.conf",
        source: "nginx.conf",
        notify: :reload_nginx

  """

  @type state :: :present | :absent
  @type condition :: term()

  @type t :: %__MODULE__{
          path: String.t(),
          state: state(),
          source: String.t() | nil,
          content: String.t() | nil,
          owner: String.t() | nil,
          group: String.t() | nil,
          mode: non_neg_integer() | nil,
          vars: map(),
          backup: boolean(),
          when: condition(),
          notify: atom() | nil
        }

  @enforce_keys [:path]
  defstruct [
    :path,
    :source,
    :content,
    :owner,
    :group,
    :mode,
    :notify,
    state: :present,
    vars: %{},
    backup: true,
    when: true
  ]

  @doc """
  Creates a new File resource.

  ## Options

    * `:state` - Target state (`:present`, `:absent`). Default `:present`.
    * `:source` - Local path to source file or template (.eex)
    * `:content` - Inline content string
    * `:owner` - File owner username
    * `:group` - File group name
    * `:mode` - File permissions (e.g., 0o644)
    * `:vars` - Variables for template rendering
    * `:backup` - Create backup before modifying. Default `true`.
    * `:notify` - Handler to trigger on change
    * `:when` - Condition for execution

  Note: Either `:source` or `:content` should be provided for `:present` state.

  Raises `ArgumentError` if validation fails.

  """
  @spec new(String.t(), keyword()) :: t()
  def new(path, opts \\ []) do
    mode = Keyword.get(opts, :mode)

    # Validate attributes
    validate!(path, mode)

    %__MODULE__{
      path: path,
      state: Keyword.get(opts, :state, :present),
      source: Keyword.get(opts, :source),
      content: Keyword.get(opts, :content),
      owner: Keyword.get(opts, :owner),
      group: Keyword.get(opts, :group),
      mode: mode,
      vars: Keyword.get(opts, :vars, %{}),
      backup: Keyword.get(opts, :backup, true),
      notify: Keyword.get(opts, :notify),
      when: Keyword.get(opts, :when, true)
    }
  end

  defp validate!(path, mode) do
    alias Nexus.Resources.Validators

    case Validators.validate_all([
           fn -> Validators.validate_path(path) end,
           fn -> Validators.validate_mode(mode) end
         ]) do
      :ok -> :ok
      {:error, msg} -> raise ArgumentError, "file resource: #{msg}"
    end
  end

  @doc """
  Returns a human-readable description of the resource.
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{path: path, state: state}) do
    "file[#{path}] state=#{state}"
  end

  @doc """
  Checks if this file resource uses a template (EEx).
  """
  @spec template?(t()) :: boolean()
  def template?(%__MODULE__{source: nil}), do: false
  def template?(%__MODULE__{source: source}), do: String.ends_with?(source, ".eex")
end

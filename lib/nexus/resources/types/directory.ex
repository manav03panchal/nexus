defmodule Nexus.Resources.Types.Directory do
  @moduledoc """
  Directory resource for managing directories on remote hosts.

  Supports:
  - Creating directories (with optional parents)
  - Setting ownership and permissions
  - Removing directories

  ## Examples

      # Create directory
      directory "/var/www/app"

      # Create with ownership and permissions
      directory "/var/www/app",
        owner: "www-data",
        group: "www-data",
        mode: 0o755

      # Create parent directories recursively
      directory "/opt/app/releases/v1.0.0", recursive: true

      # Remove directory
      directory "/tmp/cache", state: :absent

      # With conditional
      directory "/opt/app/logs",
        owner: "app",
        when: facts(:os) == :linux

  """

  @type state :: :present | :absent
  @type condition :: term()

  @type t :: %__MODULE__{
          path: String.t(),
          state: state(),
          owner: String.t() | nil,
          group: String.t() | nil,
          mode: non_neg_integer() | nil,
          recursive: boolean(),
          when: condition(),
          notify: atom() | nil
        }

  @enforce_keys [:path]
  defstruct [
    :path,
    :owner,
    :group,
    :mode,
    :notify,
    state: :present,
    recursive: false,
    when: true
  ]

  @doc """
  Creates a new Directory resource.

  ## Options

    * `:state` - Target state (`:present`, `:absent`). Default `:present`.
    * `:owner` - Directory owner username
    * `:group` - Directory group name
    * `:mode` - Directory permissions (e.g., 0o755)
    * `:recursive` - Create parent directories. Default `false`.
    * `:notify` - Handler to trigger on change
    * `:when` - Condition for execution

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
      owner: Keyword.get(opts, :owner),
      group: Keyword.get(opts, :group),
      mode: mode,
      recursive: Keyword.get(opts, :recursive, false),
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
      {:error, msg} -> raise ArgumentError, "directory resource: #{msg}"
    end
  end

  @doc """
  Returns a human-readable description of the resource.
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{path: path, state: state}) do
    "directory[#{path}] state=#{state}"
  end
end

defmodule Nexus.Types.Artifact do
  @moduledoc """
  Represents an artifact produced by a task.

  Artifacts are files that are produced by one task and consumed by
  dependent tasks. They are automatically transferred between hosts.

  ## Example

      task :build, on: :builder do
        run "make"
        artifact "build/output.tar.gz"
      end

      task :deploy, on: :web, deps: [:build] do
        # artifact is automatically available
        run "tar -xzf build/output.tar.gz"
      end

  """

  @type t :: %__MODULE__{
          path: String.t(),
          as: String.t() | nil,
          producer_task: atom() | nil
        }

  @enforce_keys [:path]
  defstruct [
    :path,
    :as,
    :producer_task
  ]

  @doc """
  Creates a new Artifact.

  ## Options

    * `:as` - Alternative name for the artifact (default: same as path)

  ## Examples

      iex> Artifact.new("build/output.tar.gz")
      %Artifact{path: "build/output.tar.gz", as: nil}

      iex> Artifact.new("dist/bundle.js", as: "app.js")
      %Artifact{path: "dist/bundle.js", as: "app.js"}

  """
  @spec new(String.t(), keyword()) :: t()
  def new(path, opts \\ []) when is_binary(path) do
    %__MODULE__{
      path: path,
      as: Keyword.get(opts, :as),
      producer_task: nil
    }
  end

  @doc """
  Returns the name used to reference this artifact.

  Uses the `:as` name if specified, otherwise the path basename.
  """
  @spec name(t()) :: String.t()
  def name(%__MODULE__{as: as}) when not is_nil(as), do: as
  def name(%__MODULE__{path: path}), do: Path.basename(path)
end

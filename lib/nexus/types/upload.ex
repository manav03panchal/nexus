defmodule Nexus.Types.Upload do
  @moduledoc """
  Represents a file upload command (local -> remote).
  """

  @type condition :: term()

  @type t :: %__MODULE__{
          local_path: String.t(),
          remote_path: String.t(),
          sudo: boolean(),
          mode: non_neg_integer() | nil,
          notify: atom() | nil,
          when: condition()
        }

  @enforce_keys [:local_path, :remote_path]
  defstruct [
    :local_path,
    :remote_path,
    :mode,
    :notify,
    sudo: false,
    when: true
  ]

  @doc """
  Creates a new Upload command.

  ## Options

    * `:sudo` - Upload to a location requiring sudo (uses temp file + mv)
    * `:mode` - File permissions to set after upload (e.g., 0o644)
    * `:notify` - Handler to trigger after upload

  ## Examples

      iex> Upload.new("dist/app.tar.gz", "/opt/app/release.tar.gz")
      %Upload{local_path: "dist/app.tar.gz", remote_path: "/opt/app/release.tar.gz"}

      iex> Upload.new("config.txt", "/etc/app/config.txt", sudo: true, mode: 0o644)
      %Upload{local_path: "config.txt", remote_path: "/etc/app/config.txt", sudo: true, mode: 0o644}

  """
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(local_path, remote_path, opts \\ [])
      when is_binary(local_path) and is_binary(remote_path) do
    %__MODULE__{
      local_path: local_path,
      remote_path: remote_path,
      sudo: Keyword.get(opts, :sudo, false),
      mode: Keyword.get(opts, :mode),
      notify: Keyword.get(opts, :notify),
      when: Keyword.get(opts, :when, true)
    }
  end
end

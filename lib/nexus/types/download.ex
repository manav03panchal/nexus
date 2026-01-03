defmodule Nexus.Types.Download do
  @moduledoc """
  Represents a file download command (remote -> local).
  """

  @type condition :: term()

  @type t :: %__MODULE__{
          remote_path: String.t(),
          local_path: String.t(),
          sudo: boolean(),
          when: condition()
        }

  @enforce_keys [:remote_path, :local_path]
  defstruct [
    :remote_path,
    :local_path,
    sudo: false,
    when: true
  ]

  @doc """
  Creates a new Download command.

  ## Options

    * `:sudo` - Download from a location requiring sudo (uses temp file)

  ## Examples

      iex> Download.new("/var/log/app.log", "logs/app.log")
      %Download{remote_path: "/var/log/app.log", local_path: "logs/app.log"}

      iex> Download.new("/etc/shadow", "shadow.bak", sudo: true)
      %Download{remote_path: "/etc/shadow", local_path: "shadow.bak", sudo: true}

  """
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(remote_path, local_path, opts \\ [])
      when is_binary(remote_path) and is_binary(local_path) do
    %__MODULE__{
      remote_path: remote_path,
      local_path: local_path,
      sudo: Keyword.get(opts, :sudo, false),
      when: Keyword.get(opts, :when, true)
    }
  end
end

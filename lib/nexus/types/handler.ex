defmodule Nexus.Types.Handler do
  @moduledoc """
  Represents a handler definition that can be triggered by notify options.

  Handlers are named blocks of commands that run when triggered by
  upload, download, or template commands with the `:notify` option.

  ## Example DSL

      handler :restart_nginx do
        run "systemctl restart nginx", sudo: true
      end

      task :configure, on: :web do
        upload "nginx.conf", "/etc/nginx/nginx.conf", notify: :restart_nginx
      end

  """

  alias Nexus.Types.Command

  @type t :: %__MODULE__{
          name: atom(),
          commands: [Command.t()]
        }

  @enforce_keys [:name]
  defstruct [
    :name,
    commands: []
  ]

  @doc """
  Creates a new Handler with the given name.

  ## Examples

      iex> Handler.new(:restart_nginx)
      %Handler{name: :restart_nginx, commands: []}

  """
  @spec new(atom()) :: t()
  def new(name) when is_atom(name) do
    %__MODULE__{name: name, commands: []}
  end

  @doc """
  Adds a command to the handler.
  """
  @spec add_command(t(), Command.t()) :: t()
  def add_command(%__MODULE__{} = handler, %Command{} = command) do
    %{handler | commands: handler.commands ++ [command]}
  end
end

defmodule Nexus.Types.Template do
  @moduledoc """
  Represents a template rendering and upload command.

  Templates are rendered locally using EEx, then uploaded to the remote host.
  """

  @type condition :: term()

  @type t :: %__MODULE__{
          source: String.t(),
          destination: String.t(),
          vars: map(),
          sudo: boolean(),
          mode: non_neg_integer() | nil,
          notify: atom() | nil,
          when: condition()
        }

  @enforce_keys [:source, :destination]
  defstruct [
    :source,
    :destination,
    :mode,
    :notify,
    vars: %{},
    sudo: false,
    when: true
  ]

  @doc """
  Creates a new Template command.

  ## Options

    * `:vars` - Map of variables to bind in the template
    * `:sudo` - Upload to a location requiring root access
    * `:mode` - File permissions to set after upload (e.g., 0o644)
    * `:notify` - Handler to trigger after template upload

  ## Examples

      iex> Template.new("templates/nginx.conf.eex", "/etc/nginx/nginx.conf")
      %Template{source: "templates/nginx.conf.eex", destination: "/etc/nginx/nginx.conf"}

      iex> Template.new("app.conf.eex", "/etc/app/config",
      ...>   vars: %{port: 8080, env: "production"},
      ...>   sudo: true,
      ...>   mode: 0o644
      ...> )
      %Template{
        source: "app.conf.eex",
        destination: "/etc/app/config",
        vars: %{port: 8080, env: "production"},
        sudo: true,
        mode: 0o644
      }

  """
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(source, destination, opts \\ [])
      when is_binary(source) and is_binary(destination) do
    %__MODULE__{
      source: source,
      destination: destination,
      vars: Keyword.get(opts, :vars, %{}),
      sudo: Keyword.get(opts, :sudo, false),
      mode: Keyword.get(opts, :mode),
      notify: Keyword.get(opts, :notify),
      when: Keyword.get(opts, :when, true)
    }
  end
end

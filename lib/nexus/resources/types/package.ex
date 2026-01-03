defmodule Nexus.Resources.Types.Package do
  @moduledoc """
  Package resource for managing system packages.

  Supports multiple package managers based on OS family:
  - apt (Debian/Ubuntu)
  - yum/dnf (RHEL/CentOS/Fedora)
  - pacman (Arch)
  - brew (macOS)
  - apk (Alpine)

  ## Examples

      # Install a single package
      package "nginx", state: :installed

      # Install with specific version
      package "nginx", state: :installed, version: "1.18.0"

      # Install multiple packages
      package ["nginx", "curl", "git"], state: :installed

      # Remove a package
      package "nginx", state: :absent

      # Ensure latest version
      package "nginx", state: :latest

      # Update cache before install
      package "nginx", state: :installed, update_cache: true

      # With conditional
      package "nginx", state: :installed, when: facts(:os_family) == :debian

  """

  @type state :: :installed | :absent | :latest
  @type condition :: term()

  @type t :: %__MODULE__{
          name: String.t() | [String.t()],
          state: state(),
          version: String.t() | nil,
          update_cache: boolean(),
          when: condition(),
          notify: atom() | nil
        }

  @enforce_keys [:name]
  defstruct [
    :name,
    :version,
    :notify,
    state: :installed,
    update_cache: false,
    when: true
  ]

  @doc """
  Creates a new Package resource.

  ## Options

    * `:state` - Target state (`:installed`, `:absent`, `:latest`). Default `:installed`.
    * `:version` - Specific version to install. Default `nil` (latest).
    * `:update_cache` - Update package cache before operation. Default `false`.
    * `:notify` - Handler to trigger on change.
    * `:when` - Condition for execution.

  """
  @spec new(String.t() | [String.t()], keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      state: Keyword.get(opts, :state, :installed),
      version: Keyword.get(opts, :version),
      update_cache: Keyword.get(opts, :update_cache, false),
      notify: Keyword.get(opts, :notify),
      when: Keyword.get(opts, :when, true)
    }
  end

  @doc """
  Returns a human-readable description of the resource.
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{name: name, state: state, version: version}) when is_list(name) do
    base = "package[#{Enum.join(name, ", ")}]"
    format_description(base, state, version)
  end

  def describe(%__MODULE__{name: name, state: state, version: version}) do
    format_description("package[#{name}]", state, version)
  end

  defp format_description(base, state, nil), do: "#{base} state=#{state}"
  defp format_description(base, state, version), do: "#{base} state=#{state} version=#{version}"
end

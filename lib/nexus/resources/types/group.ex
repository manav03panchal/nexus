defmodule Nexus.Resources.Types.Group do
  @moduledoc """
  Group resource for managing system groups.

  Supports:
  - Creating groups with optional GID
  - Creating system groups
  - Removing groups

  ## Examples

      # Create basic group
      group "developers"

      # Create with specific GID
      group "developers", gid: 1001

      # Create system group
      group "app", system: true

      # Remove group
      group "oldgroup", state: :absent

      # With conditional
      group "docker", when: facts(:os) == :linux

  """

  @type state :: :present | :absent
  @type condition :: term()

  @type t :: %__MODULE__{
          name: String.t(),
          state: state(),
          gid: non_neg_integer() | nil,
          system: boolean(),
          when: condition(),
          notify: atom() | nil
        }

  @enforce_keys [:name]
  defstruct [
    :name,
    :gid,
    :notify,
    state: :present,
    system: false,
    when: true
  ]

  @doc """
  Creates a new Group resource.

  ## Options

    * `:state` - Target state (`:present`, `:absent`). Default `:present`.
    * `:gid` - Group ID number
    * `:system` - Create as system group. Default `false`.
    * `:notify` - Handler to trigger on change
    * `:when` - Condition for execution

  """
  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      state: Keyword.get(opts, :state, :present),
      gid: Keyword.get(opts, :gid),
      system: Keyword.get(opts, :system, false),
      notify: Keyword.get(opts, :notify),
      when: Keyword.get(opts, :when, true)
    }
  end

  @doc """
  Returns a human-readable description of the resource.
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{name: name, state: state, gid: nil}) do
    "group[#{name}] state=#{state}"
  end

  def describe(%__MODULE__{name: name, state: state, gid: gid}) do
    "group[#{name}] state=#{state} gid=#{gid}"
  end
end

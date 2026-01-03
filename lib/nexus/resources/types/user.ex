defmodule Nexus.Resources.Types.User do
  @moduledoc """
  User resource for managing system users.

  Supports:
  - Creating users with home directories
  - Setting group memberships
  - Configuring shell and other attributes
  - Removing users

  ## Examples

      # Create basic user
      user "deploy"

      # Create with groups and shell
      user "deploy",
        groups: ["sudo", "docker"],
        shell: "/bin/bash",
        home: "/home/deploy"

      # Create system user (no home, no login)
      user "app",
        system: true,
        shell: "/usr/sbin/nologin"

      # Create with specific UID
      user "deploy", uid: 1001, gid: 1001

      # Remove user
      user "olduser", state: :absent

      # With comment (GECOS)
      user "deploy",
        comment: "Deployment User",
        groups: ["www-data"]

  """

  @type state :: :present | :absent
  @type condition :: term()

  @type t :: %__MODULE__{
          name: String.t(),
          state: state(),
          uid: non_neg_integer() | nil,
          gid: non_neg_integer() | nil,
          groups: [String.t()],
          shell: String.t() | nil,
          home: String.t() | nil,
          comment: String.t() | nil,
          system: boolean(),
          when: condition(),
          notify: atom() | nil
        }

  @enforce_keys [:name]
  defstruct [
    :name,
    :uid,
    :gid,
    :shell,
    :home,
    :comment,
    :notify,
    state: :present,
    groups: [],
    system: false,
    when: true
  ]

  @doc """
  Creates a new User resource.

  ## Options

    * `:state` - Target state (`:present`, `:absent`). Default `:present`.
    * `:uid` - User ID number
    * `:gid` - Primary group ID number
    * `:groups` - List of supplementary groups. Default `[]`.
    * `:shell` - Login shell path
    * `:home` - Home directory path
    * `:comment` - GECOS/comment field
    * `:system` - Create as system user. Default `false`.
    * `:notify` - Handler to trigger on change
    * `:when` - Condition for execution

  Raises `ArgumentError` if validation fails.

  """
  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    uid = Keyword.get(opts, :uid)
    gid = Keyword.get(opts, :gid)
    shell = Keyword.get(opts, :shell)
    home = Keyword.get(opts, :home)

    # Validate attributes
    validate!(name, uid, gid, shell, home)

    %__MODULE__{
      name: name,
      state: Keyword.get(opts, :state, :present),
      uid: uid,
      gid: gid,
      groups: Keyword.get(opts, :groups, []),
      shell: shell,
      home: home,
      comment: Keyword.get(opts, :comment),
      system: Keyword.get(opts, :system, false),
      notify: Keyword.get(opts, :notify),
      when: Keyword.get(opts, :when, true)
    }
  end

  defp validate!(name, uid, gid, shell, home) do
    alias Nexus.Resources.Validators

    case Validators.validate_all([
           fn -> Validators.validate_username(name) end,
           fn -> Validators.validate_id(uid) end,
           fn -> Validators.validate_id(gid) end,
           fn -> Validators.validate_shell(shell) end,
           fn -> Validators.validate_path(home) end
         ]) do
      :ok -> :ok
      {:error, msg} -> raise ArgumentError, "user resource: #{msg}"
    end
  end

  @doc """
  Returns a human-readable description of the resource.
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{name: name, state: state, groups: groups}) do
    base = "user[#{name}] state=#{state}"

    if groups != [] do
      "#{base} groups=#{inspect(groups)}"
    else
      base
    end
  end
end

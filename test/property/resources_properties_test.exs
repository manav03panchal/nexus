defmodule Nexus.Resources.PropertiesTest do
  @moduledoc """
  Property-based tests for resource types.

  Tests that:
  - Resource creation preserves all attributes
  - Validation catches invalid inputs
  - Edge cases are handled correctly
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  @moduletag :property

  alias Nexus.Resources.Types.{Command, Directory, File, Group, Package, Service, User}
  alias Nexus.Resources.Validators

  # ============================================================================
  # Generators
  # ============================================================================

  defp valid_path do
    gen all(
          parts <-
            StreamData.list_of(
              StreamData.string([?a..?z, ?0..?9, ?_, ?-], min_length: 1, max_length: 15),
              min_length: 1,
              max_length: 5
            )
        ) do
      "/" <> Enum.join(parts, "/")
    end
  end

  defp invalid_path do
    gen all(
          parts <-
            StreamData.list_of(
              StreamData.string([?a..?z, ?0..?9, ?_, ?-], min_length: 1, max_length: 10),
              min_length: 1,
              max_length: 3
            )
        ) do
      # Relative path (no leading /)
      Enum.join(parts, "/")
    end
  end

  defp valid_mode do
    StreamData.integer(0..0o7777)
  end

  defp invalid_mode do
    gen all(mode <- StreamData.integer(0o10000..0o77777)) do
      mode
    end
  end

  defp valid_username do
    gen all(
          first <- StreamData.string(?a..?z, min_length: 1, max_length: 1),
          rest <- StreamData.string([?a..?z, ?0..?9, ?_], max_length: 10)
        ) do
      first <> rest
    end
  end

  defp invalid_username do
    gen all(
          # Start with number
          first <- StreamData.string(?0..?9, min_length: 1, max_length: 1),
          rest <- StreamData.string(:alphanumeric, max_length: 10)
        ) do
      first <> rest
    end
  end

  defp valid_package_name do
    StreamData.string([?a..?z, ?0..?9, ?., ?_, ?+, ?-, ?@], min_length: 1, max_length: 30)
  end

  defp valid_service_name do
    StreamData.string([?a..?z, ?0..?9, ?., ?_, ?-, ?@], min_length: 1, max_length: 30)
  end

  defp valid_command_string do
    gen all(
          cmd <- StreamData.member_of(["echo", "ls", "cat", "pwd", "test", "mkdir", "rm"]),
          args <- StreamData.string(:alphanumeric, max_length: 30)
        ) do
      if args == "", do: cmd, else: "#{cmd} #{args}"
    end
  end

  defp valid_state do
    StreamData.member_of([:present, :absent])
  end

  defp valid_owner do
    StreamData.one_of([StreamData.constant(nil), valid_username()])
  end

  # ============================================================================
  # Directory Resource Tests
  # ============================================================================

  describe "Directory resource" do
    property "preserves path" do
      check all(path <- valid_path()) do
        dir = Directory.new(path)
        assert dir.path == path
      end
    end

    property "preserves mode" do
      check all(
              path <- valid_path(),
              mode <- valid_mode()
            ) do
        dir = Directory.new(path, mode: mode)
        assert dir.mode == mode
      end
    end

    property "preserves state" do
      check all(
              path <- valid_path(),
              state <- valid_state()
            ) do
        dir = Directory.new(path, state: state)
        assert dir.state == state
      end
    end

    property "preserves owner and group" do
      check all(
              path <- valid_path(),
              owner <- valid_owner(),
              group <- valid_owner()
            ) do
        dir = Directory.new(path, owner: owner, group: group)
        assert dir.owner == owner
        assert dir.group == group
      end
    end

    property "rejects relative paths" do
      check all(path <- invalid_path()) do
        assert_raise ArgumentError, ~r/path must be absolute/, fn ->
          Directory.new(path)
        end
      end
    end

    property "rejects invalid modes" do
      check all(
              path <- valid_path(),
              mode <- invalid_mode()
            ) do
        assert_raise ArgumentError, ~r/invalid mode/, fn ->
          Directory.new(path, mode: mode)
        end
      end
    end

    property "describe includes path and state" do
      check all(
              path <- valid_path(),
              state <- valid_state()
            ) do
        dir = Directory.new(path, state: state)
        desc = Directory.describe(dir)
        assert desc =~ path
        assert desc =~ to_string(state)
      end
    end
  end

  # ============================================================================
  # File Resource Tests
  # ============================================================================

  describe "File resource" do
    property "preserves path" do
      check all(path <- valid_path()) do
        file = File.new(path)
        assert file.path == path
      end
    end

    property "preserves content" do
      check all(
              path <- valid_path(),
              content <- StreamData.string(:printable, max_length: 100)
            ) do
        file = File.new(path, content: content)
        assert file.content == content
      end
    end

    property "preserves mode" do
      check all(
              path <- valid_path(),
              mode <- valid_mode()
            ) do
        file = File.new(path, mode: mode)
        assert file.mode == mode
      end
    end

    property "preserves source" do
      check all(
              path <- valid_path(),
              source <- valid_path()
            ) do
        file = File.new(path, source: source)
        assert file.source == source
      end
    end

    property "template? returns true for .eex files" do
      check all(
              path <- valid_path(),
              source_base <- StreamData.string(?a..?z, min_length: 1, max_length: 10)
            ) do
        source = "/templates/#{source_base}.eex"
        file = File.new(path, source: source)
        assert File.template?(file)
      end
    end

    property "template? returns false for non-.eex files" do
      check all(
              path <- valid_path(),
              source_base <- StreamData.string(?a..?z, min_length: 1, max_length: 10)
            ) do
        source = "/templates/#{source_base}.txt"
        file = File.new(path, source: source)
        refute File.template?(file)
      end
    end

    property "rejects relative paths" do
      check all(path <- invalid_path()) do
        assert_raise ArgumentError, ~r/path must be absolute/, fn ->
          File.new(path)
        end
      end
    end

    property "rejects invalid modes" do
      check all(
              path <- valid_path(),
              mode <- invalid_mode()
            ) do
        assert_raise ArgumentError, ~r/invalid mode/, fn ->
          File.new(path, mode: mode)
        end
      end
    end
  end

  # ============================================================================
  # Command Resource Tests
  # ============================================================================

  describe "Command resource" do
    property "preserves command string" do
      check all(cmd <- valid_command_string()) do
        command = Command.new(cmd)
        assert command.cmd == cmd
      end
    end

    property "preserves creates guard" do
      check all(
              cmd <- valid_command_string(),
              creates <- valid_path()
            ) do
        command = Command.new(cmd, creates: creates)
        assert command.creates == creates
      end
    end

    property "preserves removes guard" do
      check all(
              cmd <- valid_command_string(),
              removes <- valid_path()
            ) do
        command = Command.new(cmd, removes: removes)
        assert command.removes == removes
      end
    end

    property "preserves unless guard" do
      check all(
              cmd <- valid_command_string(),
              unless_cmd <- valid_command_string()
            ) do
        command = Command.new(cmd, unless: unless_cmd)
        assert command.unless == unless_cmd
      end
    end

    property "preserves onlyif guard" do
      check all(
              cmd <- valid_command_string(),
              onlyif_cmd <- valid_command_string()
            ) do
        command = Command.new(cmd, onlyif: onlyif_cmd)
        assert command.onlyif == onlyif_cmd
      end
    end

    property "preserves environment variables" do
      check all(
              cmd <- valid_command_string(),
              env_key <- StreamData.string(?A..?Z, min_length: 1, max_length: 10),
              env_val <- StreamData.string(:alphanumeric, max_length: 20)
            ) do
        env = %{env_key => env_val}
        command = Command.new(cmd, env: env)
        assert command.env == env
      end
    end

    property "preserves working directory" do
      check all(
              cmd <- valid_command_string(),
              cwd <- valid_path()
            ) do
        command = Command.new(cmd, cwd: cwd)
        assert command.cwd == cwd
      end
    end

    property "preserves sudo option" do
      check all(
              cmd <- valid_command_string(),
              sudo <- StreamData.boolean()
            ) do
        command = Command.new(cmd, sudo: sudo)
        assert command.sudo == sudo
      end
    end
  end

  # ============================================================================
  # Package Resource Tests
  # ============================================================================

  describe "Package resource" do
    property "preserves single package name" do
      check all(name <- valid_package_name()) do
        pkg = Package.new(name)
        assert pkg.name == name
      end
    end

    property "preserves list of package names" do
      check all(names <- StreamData.list_of(valid_package_name(), min_length: 1, max_length: 5)) do
        pkg = Package.new(names)
        assert pkg.name == names
      end
    end

    property "preserves state" do
      check all(
              name <- valid_package_name(),
              state <- StreamData.member_of([:installed, :latest, :absent])
            ) do
        pkg = Package.new(name, state: state)
        assert pkg.state == state
      end
    end

    property "preserves version" do
      check all(
              name <- valid_package_name(),
              version <- StreamData.string(:alphanumeric, min_length: 1, max_length: 10)
            ) do
        pkg = Package.new(name, version: version)
        assert pkg.version == version
      end
    end
  end

  # ============================================================================
  # Service Resource Tests
  # ============================================================================

  describe "Service resource" do
    property "preserves name" do
      check all(name <- valid_service_name()) do
        svc = Service.new(name)
        assert svc.name == name
      end
    end

    property "preserves state" do
      check all(
              name <- valid_service_name(),
              state <- StreamData.member_of([:running, :stopped])
            ) do
        svc = Service.new(name, state: state)
        assert svc.state == state
      end
    end

    property "preserves enabled" do
      check all(
              name <- valid_service_name(),
              enabled <- StreamData.boolean()
            ) do
        svc = Service.new(name, enabled: enabled)
        assert svc.enabled == enabled
      end
    end

    property "preserves action" do
      check all(
              name <- valid_service_name(),
              action <-
                StreamData.member_of([:start, :stop, :restart, :reload, :enable, :disable])
            ) do
        svc = Service.new(name, action: action)
        assert svc.action == action
      end
    end
  end

  # ============================================================================
  # User Resource Tests
  # ============================================================================

  describe "User resource" do
    property "preserves name" do
      check all(name <- valid_username()) do
        user = User.new(name)
        assert user.name == name
      end
    end

    property "preserves uid" do
      check all(
              name <- valid_username(),
              uid <- StreamData.integer(0..65_535)
            ) do
        user = User.new(name, uid: uid)
        assert user.uid == uid
      end
    end

    property "preserves gid" do
      check all(
              name <- valid_username(),
              gid <- StreamData.integer(0..65_535)
            ) do
        user = User.new(name, gid: gid)
        assert user.gid == gid
      end
    end

    property "preserves groups" do
      check all(
              name <- valid_username(),
              groups <- StreamData.list_of(valid_username(), max_length: 5)
            ) do
        user = User.new(name, groups: groups)
        assert user.groups == groups
      end
    end

    property "preserves shell" do
      check all(
              name <- valid_username(),
              shell <- valid_path()
            ) do
        user = User.new(name, shell: shell)
        assert user.shell == shell
      end
    end

    property "preserves home" do
      check all(
              name <- valid_username(),
              home <- valid_path()
            ) do
        user = User.new(name, home: home)
        assert user.home == home
      end
    end

    property "preserves system flag" do
      check all(
              name <- valid_username(),
              system <- StreamData.boolean()
            ) do
        user = User.new(name, system: system)
        assert user.system == system
      end
    end

    property "rejects invalid usernames" do
      check all(name <- invalid_username()) do
        assert_raise ArgumentError, ~r/invalid username/, fn ->
          User.new(name)
        end
      end
    end

    property "rejects negative uid" do
      check all(
              name <- valid_username(),
              uid <- StreamData.integer(-1000..-1)
            ) do
        assert_raise ArgumentError, ~r/invalid id/, fn ->
          User.new(name, uid: uid)
        end
      end
    end

    property "rejects relative shell path" do
      check all(
              name <- valid_username(),
              shell <- invalid_path()
            ) do
        assert_raise ArgumentError, ~r/shell must be absolute/, fn ->
          User.new(name, shell: shell)
        end
      end
    end
  end

  # ============================================================================
  # Group Resource Tests
  # ============================================================================

  describe "Group resource" do
    property "preserves name" do
      check all(name <- valid_username()) do
        grp = Group.new(name)
        assert grp.name == name
      end
    end

    property "preserves gid" do
      check all(
              name <- valid_username(),
              gid <- StreamData.integer(0..65_535)
            ) do
        grp = Group.new(name, gid: gid)
        assert grp.gid == gid
      end
    end

    property "preserves state" do
      check all(
              name <- valid_username(),
              state <- valid_state()
            ) do
        grp = Group.new(name, state: state)
        assert grp.state == state
      end
    end
  end

  # ============================================================================
  # Validators Tests
  # ============================================================================

  describe "Validators" do
    property "validate_path accepts absolute paths" do
      check all(path <- valid_path()) do
        assert Validators.validate_path(path) == :ok
      end
    end

    property "validate_path rejects relative paths" do
      check all(path <- invalid_path()) do
        assert {:error, _} = Validators.validate_path(path)
      end
    end

    property "validate_mode accepts valid modes" do
      check all(mode <- valid_mode()) do
        assert Validators.validate_mode(mode) == :ok
      end
    end

    property "validate_mode rejects invalid modes" do
      check all(mode <- invalid_mode()) do
        assert {:error, _} = Validators.validate_mode(mode)
      end
    end

    property "validate_username accepts valid usernames" do
      check all(name <- valid_username()) do
        assert Validators.validate_username(name) == :ok
      end
    end

    property "validate_username rejects invalid usernames" do
      check all(name <- invalid_username()) do
        assert {:error, _} = Validators.validate_username(name)
      end
    end

    property "validate_id accepts non-negative integers" do
      check all(id <- StreamData.integer(0..65_535)) do
        assert Validators.validate_id(id) == :ok
      end
    end

    property "validate_id rejects negative integers" do
      check all(id <- StreamData.integer(-1000..-1)) do
        assert {:error, _} = Validators.validate_id(id)
      end
    end

    property "validate_shell accepts absolute paths" do
      check all(shell <- valid_path()) do
        assert Validators.validate_shell(shell) == :ok
      end
    end

    property "validate_shell rejects relative paths" do
      check all(shell <- invalid_path()) do
        assert {:error, _} = Validators.validate_shell(shell)
      end
    end

    property "validate_state accepts valid states" do
      check all(state <- valid_state()) do
        assert Validators.validate_state(state, [:present, :absent]) == :ok
      end
    end

    property "validate_state rejects invalid states" do
      check all(state <- StreamData.member_of([:invalid, :unknown, :bad, :wrong, :nope])) do
        assert {:error, _} = Validators.validate_state(state, [:present, :absent])
      end
    end

    property "validate_all returns :ok when all pass" do
      check all(
              path <- valid_path(),
              mode <- valid_mode()
            ) do
        result =
          Validators.validate_all([
            fn -> Validators.validate_path(path) end,
            fn -> Validators.validate_mode(mode) end
          ])

        assert result == :ok
      end
    end

    property "validate_all returns first error" do
      check all(
              path <- invalid_path(),
              mode <- valid_mode()
            ) do
        result =
          Validators.validate_all([
            fn -> Validators.validate_path(path) end,
            fn -> Validators.validate_mode(mode) end
          ])

        assert {:error, msg} = result
        assert msg =~ "path must be absolute"
      end
    end
  end
end

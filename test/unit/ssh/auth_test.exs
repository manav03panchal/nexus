defmodule Nexus.SSH.AuthTest do
  use ExUnit.Case, async: true

  alias Nexus.SSH.Auth

  @moduletag :unit

  describe "resolve/2" do
    test "uses explicit identity when provided" do
      # Create a temp key file
      tmp_dir = System.tmp_dir!()
      key_path = Path.join(tmp_dir, "test_key_#{:rand.uniform(10000)}")
      File.write!(key_path, "fake key content")

      on_exit(fn -> File.rm(key_path) end)

      {:ok, opts} = Auth.resolve("example.com", identity: key_path)

      assert Keyword.get(opts, :identity) == key_path
    end

    test "returns error for non-existent identity file" do
      {:error, {:identity_not_found, _path}} =
        Auth.resolve("example.com", identity: "/nonexistent/key")
    end

    test "returns error for directory as identity" do
      {:error, {:identity_not_file, _path}} =
        Auth.resolve("example.com", identity: System.tmp_dir!())
    end

    test "uses password when provided" do
      {:ok, opts} = Auth.resolve("example.com", password: "secret")

      assert Keyword.get(opts, :password) == "secret"
    end

    test "passes through user option" do
      {:ok, opts} = Auth.resolve("example.com", user: "deploy", password: "secret")

      assert Keyword.get(opts, :user) == "deploy"
    end

    test "returns ok without explicit auth method" do
      # This test works when no default keys exist or agent isn't available
      {:ok, _opts} = Auth.resolve("example.com", prefer_agent: false)
    end
  end

  describe "method/1" do
    test "detects identity method" do
      opts = [identity: "/path/to/key"]
      assert {:identity, "/path/to/key"} = Auth.method(opts)
    end

    test "detects password method" do
      opts = [password: "secret"]
      assert {:password, "***"} = Auth.method(opts)
    end

    test "returns :none for empty opts without agent" do
      # Mock agent unavailable by temporarily unsetting SSH_AUTH_SOCK
      original = System.get_env("SSH_AUTH_SOCK")

      try do
        System.delete_env("SSH_AUTH_SOCK")
        assert :none = Auth.method([])
      after
        if original, do: System.put_env("SSH_AUTH_SOCK", original)
      end
    end
  end

  describe "agent_available?/0" do
    test "returns false when SSH_AUTH_SOCK is not set" do
      original = System.get_env("SSH_AUTH_SOCK")

      try do
        System.delete_env("SSH_AUTH_SOCK")
        refute Auth.agent_available?()
      after
        if original, do: System.put_env("SSH_AUTH_SOCK", original)
      end
    end

    test "returns false when SSH_AUTH_SOCK is empty" do
      original = System.get_env("SSH_AUTH_SOCK")

      try do
        System.put_env("SSH_AUTH_SOCK", "")
        refute Auth.agent_available?()
      after
        if original do
          System.put_env("SSH_AUTH_SOCK", original)
        else
          System.delete_env("SSH_AUTH_SOCK")
        end
      end
    end

    test "returns false when socket path doesn't exist" do
      original = System.get_env("SSH_AUTH_SOCK")

      try do
        System.put_env("SSH_AUTH_SOCK", "/nonexistent/socket")
        refute Auth.agent_available?()
      after
        if original do
          System.put_env("SSH_AUTH_SOCK", original)
        else
          System.delete_env("SSH_AUTH_SOCK")
        end
      end
    end
  end

  describe "available_keys/0" do
    test "returns list of paths" do
      keys = Auth.available_keys()
      assert is_list(keys)

      # All returned paths should be strings
      Enum.each(keys, fn path ->
        assert is_binary(path)
        assert File.exists?(path)
      end)
    end
  end

  describe "ssh_directory/0" do
    test "returns expanded path ending in .ssh" do
      dir = Auth.ssh_directory()
      assert String.ends_with?(dir, ".ssh")
      assert String.starts_with?(dir, "/")
    end
  end
end

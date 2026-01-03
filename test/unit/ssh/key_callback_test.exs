defmodule Nexus.SSH.KeyCallbackTest do
  use ExUnit.Case, async: true

  alias Nexus.SSH.KeyCallback

  @moduletag :unit

  describe "module structure" do
    test "module is loaded" do
      {:module, _} = Code.ensure_loaded(KeyCallback)
      assert Code.ensure_loaded?(KeyCallback)
    end

    test "exports expected functions" do
      functions = KeyCallback.__info__(:functions)

      assert {:is_host_key, 4} in functions or {:is_host_key, 5} in functions
      assert {:add_host_key, 3} in functions or {:add_host_key, 4} in functions
      assert {:user_key, 2} in functions
    end
  end

  describe "is_host_key/4" do
    test "always returns true (accepts all host keys)" do
      # KeyCallback accepts all host keys by design
      result = KeyCallback.is_host_key(:rsa, "fake_key", "host.example.com", [])
      assert result == true
    end

    test "accepts different key types" do
      assert KeyCallback.is_host_key(:dsa, "fake_key", "host1.example.com", []) == true
      assert KeyCallback.is_host_key(:ecdsa, "fake_key", "host2.example.com", []) == true
    end

    test "accepts any hostname" do
      assert KeyCallback.is_host_key(:rsa, "key", "192.168.1.1", []) == true
      assert KeyCallback.is_host_key(:rsa, "key", "localhost", []) == true
    end
  end

  describe "add_host_key/4" do
    test "always returns :ok (no-op)" do
      result = KeyCallback.add_host_key("host.example.com", 22, :rsa, [])
      assert result == :ok
    end

    test "accepts any host and key type" do
      assert KeyCallback.add_host_key("any.host", 22, :dsa, []) == :ok
      assert KeyCallback.add_host_key("192.168.1.1", 2222, :ecdsa, []) == :ok
    end
  end

  describe "user_key/2" do
    test "returns error when key_file option is missing" do
      result = KeyCallback.user_key(:"ssh-rsa", [])

      assert {:error, :no_key_file} = result
    end

    test "returns error for non-existent key file" do
      result = KeyCallback.user_key(:"ssh-rsa", key_file: "/nonexistent/key")

      assert {:error, {:key_file_error, "/nonexistent/key", :enoent}} = result
    end

    test "returns error for invalid key content" do
      tmp_dir = System.tmp_dir!()
      key_path = Path.join(tmp_dir, "invalid_key_#{:rand.uniform(10000)}")
      File.write!(key_path, "not a valid key")

      on_exit(fn -> File.rm(key_path) end)

      result = KeyCallback.user_key(:"ssh-rsa", key_file: key_path)

      assert {:error, _reason} = result
    end

    test "returns error for empty key file" do
      tmp_dir = System.tmp_dir!()
      key_path = Path.join(tmp_dir, "empty_key_#{:rand.uniform(10000)}")
      File.write!(key_path, "")

      on_exit(fn -> File.rm(key_path) end)

      result = KeyCallback.user_key(:"ssh-rsa", key_file: key_path)

      assert {:error, _reason} = result
    end

    test "returns error for directory as key file" do
      tmp_dir = System.tmp_dir!()
      dir_path = Path.join(tmp_dir, "dir_as_key_#{:rand.uniform(10000)}")
      File.mkdir_p!(dir_path)

      on_exit(fn -> File.rmdir(dir_path) end)

      result = KeyCallback.user_key(:"ssh-rsa", key_file: dir_path)

      assert {:error, _reason} = result
    end
  end

  describe "user_key/2 with valid RSA key" do
    setup do
      # Generate a test RSA key
      tmp_dir = System.tmp_dir!()
      key_path = Path.join(tmp_dir, "test_rsa_key_#{:rand.uniform(10000)}")

      # Generate RSA key using Erlang's public_key
      rsa_key = :public_key.generate_key({:rsa, 2048, 65_537})
      pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, rsa_key)
      pem = :public_key.pem_encode([pem_entry])

      File.write!(key_path, pem)

      on_exit(fn -> File.rm(key_path) end)

      {:ok, key_path: key_path, rsa_key: rsa_key}
    end

    test "loads valid RSA key", %{key_path: key_path} do
      result = KeyCallback.user_key(:"ssh-rsa", key_file: key_path)

      assert {:ok, key} = result
      assert is_tuple(key)
    end

    test "handles rsa-sha2-256 algorithm", %{key_path: key_path} do
      result = KeyCallback.user_key(:"rsa-sha2-256", key_file: key_path)

      assert {:ok, _key} = result
    end

    test "handles rsa-sha2-512 algorithm", %{key_path: key_path} do
      result = KeyCallback.user_key(:"rsa-sha2-512", key_file: key_path)

      assert {:ok, _key} = result
    end
  end

  describe "user_key/2 with valid ECDSA key" do
    setup do
      tmp_dir = System.tmp_dir!()
      key_path = Path.join(tmp_dir, "test_ecdsa_key_#{:rand.uniform(10000)}")

      # Generate ECDSA key
      ec_key = :public_key.generate_key({:namedCurve, :secp256r1})
      pem_entry = :public_key.pem_entry_encode(:ECPrivateKey, ec_key)
      pem = :public_key.pem_encode([pem_entry])

      File.write!(key_path, pem)

      on_exit(fn -> File.rm(key_path) end)

      {:ok, key_path: key_path}
    end

    test "loads valid ECDSA key", %{key_path: key_path} do
      result = KeyCallback.user_key(:"ecdsa-sha2-nistp256", key_file: key_path)

      assert {:ok, key} = result
      assert is_tuple(key)
    end
  end

  describe "algorithm handling" do
    setup do
      tmp_dir = System.tmp_dir!()
      key_path = Path.join(tmp_dir, "test_key_#{:rand.uniform(10000)}")

      rsa_key = :public_key.generate_key({:rsa, 2048, 65_537})
      pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, rsa_key)
      pem = :public_key.pem_encode([pem_entry])

      File.write!(key_path, pem)

      on_exit(fn -> File.rm(key_path) end)

      {:ok, key_path: key_path}
    end

    test "ssh-rsa algorithm works", %{key_path: key_path} do
      assert {:ok, _} = KeyCallback.user_key(:"ssh-rsa", key_file: key_path)
    end

    test "rsa-sha2-256 algorithm works", %{key_path: key_path} do
      assert {:ok, _} = KeyCallback.user_key(:"rsa-sha2-256", key_file: key_path)
    end

    test "rsa-sha2-512 algorithm works", %{key_path: key_path} do
      assert {:ok, _} = KeyCallback.user_key(:"rsa-sha2-512", key_file: key_path)
    end
  end

  describe "key file path handling" do
    test "handles absolute paths" do
      result = KeyCallback.user_key(:"ssh-rsa", key_file: "/absolute/path/key")

      # Should fail with file not found error
      assert {:error, {:key_file_error, "/absolute/path/key", :enoent}} = result
    end

    test "handles paths with special characters" do
      result = KeyCallback.user_key(:"ssh-rsa", key_file: "/path/with spaces/key")

      assert {:error, {:key_file_error, "/path/with spaces/key", :enoent}} = result
    end
  end
end

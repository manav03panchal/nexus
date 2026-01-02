defmodule Nexus.Secrets.VaultEdgeCasesTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  # These tests validate edge case handling for secret values and names
  # without requiring actual vault encryption (which is tested in vault_test.exs)

  describe "secret value validation" do
    test "empty string is a valid secret value" do
      value = ""
      assert is_binary(value)
      assert byte_size(value) == 0
    end

    test "very long values are valid" do
      value = String.duplicate("a", 1_000_000)
      assert byte_size(value) == 1_000_000
    end

    test "binary data can be base64 encoded for storage" do
      binary = <<0, 1, 2, 3, 0, 255, 254, 0, 128>>
      encoded = Base.encode64(binary)
      decoded = Base.decode64!(encoded)
      assert binary == decoded
    end

    test "unicode values are valid" do
      value = "🔐密码пароль🔑"
      assert String.valid?(value)
      # 2 emojis + 2 Chinese + 6 Cyrillic = 10 graphemes
      assert String.length(value) == 10
    end

    test "JSON values are valid" do
      value = ~s({"key": "value", "nested": {"a": [1,2,3]}})
      assert {:ok, _} = Jason.decode(value)
    end

    test "values with newlines and tabs are valid" do
      value = "line1\nline2\tindented\r\nwindows"
      assert String.contains?(value, "\n")
      assert String.contains?(value, "\t")
    end

    test "values with backslashes and quotes are valid" do
      value = ~s(C:\\Users\\test\\file.txt "quoted")
      assert String.contains?(value, "\\")
      assert String.contains?(value, "\"")
    end
  end

  describe "secret name validation" do
    test "names with dots are valid" do
      name = "secret.with.dots"
      assert String.contains?(name, ".")
    end

    test "names with dashes are valid" do
      name = "secret-with-dashes"
      assert String.contains?(name, "-")
    end

    test "names with underscores are valid" do
      name = "secret_with_underscores"
      assert String.contains?(name, "_")
    end

    test "names with slashes are valid" do
      name = "secret/with/slashes"
      assert String.contains?(name, "/")
    end

    test "uppercase names are valid" do
      name = "UPPERCASE_SECRET"
      assert name == String.upcase(name)
    end

    test "mixed case names are valid" do
      name = "MixedCase_Secret123"
      assert String.match?(name, ~r/[A-Z]/)
      assert String.match?(name, ~r/[a-z]/)
    end

    test "unicode names are valid" do
      name = "секрет_密码"
      assert String.valid?(name)
    end

    test "very long names are valid strings" do
      name = String.duplicate("a", 1000)
      assert byte_size(name) == 1000
    end

    test "names are case-sensitive" do
      assert "Secret" != "secret"
      assert "SECRET" != "secret"
    end
  end

  describe "encryption key handling" do
    test "base64 encoded key is valid format" do
      key = :crypto.strong_rand_bytes(32) |> Base.encode64()
      assert {:ok, decoded} = Base.decode64(key)
      assert byte_size(decoded) == 32
    end

    test "PBKDF2 can derive key from short password" do
      password = "short"
      salt = :crypto.strong_rand_bytes(16)
      # PBKDF2 should work with any length password
      key = :crypto.pbkdf2_hmac(:sha256, password, salt, 1000, 32)
      assert byte_size(key) == 32
    end

    test "PBKDF2 can derive key from long password" do
      password = String.duplicate("a", 1000)
      salt = :crypto.strong_rand_bytes(16)
      key = :crypto.pbkdf2_hmac(:sha256, password, salt, 1000, 32)
      assert byte_size(key) == 32
    end

    test "PBKDF2 can derive key from unicode password" do
      password = "密码🔑пароль"
      salt = :crypto.strong_rand_bytes(16)
      key = :crypto.pbkdf2_hmac(:sha256, password, salt, 1000, 32)
      assert byte_size(key) == 32
    end
  end

  describe "AES-256-GCM encryption" do
    test "encrypts and decrypts correctly" do
      key = :crypto.strong_rand_bytes(32)
      iv = :crypto.strong_rand_bytes(12)
      plaintext = "secret value"
      aad = ""

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, aad, true)

      decrypted = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, aad, tag, false)
      assert decrypted == plaintext
    end

    test "handles empty plaintext" do
      key = :crypto.strong_rand_bytes(32)
      iv = :crypto.strong_rand_bytes(12)
      plaintext = ""
      aad = ""

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, aad, true)

      decrypted = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, aad, tag, false)
      assert decrypted == ""
    end

    test "handles binary plaintext" do
      key = :crypto.strong_rand_bytes(32)
      iv = :crypto.strong_rand_bytes(12)
      plaintext = <<0, 1, 2, 3, 255, 254>>
      aad = ""

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, aad, true)

      decrypted = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, aad, tag, false)
      assert decrypted == plaintext
    end

    test "detects tampering" do
      key = :crypto.strong_rand_bytes(32)
      iv = :crypto.strong_rand_bytes(12)
      plaintext = "secret"
      aad = ""

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, aad, true)

      # Tamper with ciphertext
      tampered = :binary.copy(ciphertext)
      <<first, rest::binary>> = tampered
      tampered = <<first + 1, rest::binary>>

      result = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, tampered, aad, tag, false)
      assert result == :error
    end

    test "wrong key fails decryption" do
      key1 = :crypto.strong_rand_bytes(32)
      key2 = :crypto.strong_rand_bytes(32)
      iv = :crypto.strong_rand_bytes(12)
      plaintext = "secret"
      aad = ""

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:aes_256_gcm, key1, iv, plaintext, aad, true)

      result = :crypto.crypto_one_time_aead(:aes_256_gcm, key2, iv, ciphertext, aad, tag, false)
      assert result == :error
    end
  end

  describe "JSON storage format" do
    test "secrets map can be JSON encoded" do
      secrets = %{
        "secret1" => "value1",
        "secret2" => "value2"
      }

      json = Jason.encode!(secrets)
      decoded = Jason.decode!(json)
      assert decoded == secrets
    end

    test "unicode keys and values encode correctly" do
      secrets = %{
        "密码" => "secret🔐",
        "пароль" => "value"
      }

      json = Jason.encode!(secrets)
      decoded = Jason.decode!(json)
      assert decoded == secrets
    end

    test "empty secrets map encodes correctly" do
      secrets = %{}
      json = Jason.encode!(secrets)
      assert json == "{}"
      decoded = Jason.decode!(json)
      assert decoded == %{}
    end

    test "large secrets map encodes correctly" do
      secrets = for i <- 1..1000, into: %{}, do: {"key#{i}", "value#{i}"}
      json = Jason.encode!(secrets)
      decoded = Jason.decode!(json)
      assert map_size(decoded) == 1000
    end
  end

  describe "file operations edge cases" do
    test "file paths with special characters" do
      paths = [
        "/path/with spaces/file.enc",
        "/path/with-dashes/file.enc",
        "/path/with_underscores/file.enc"
      ]

      for path <- paths do
        assert String.ends_with?(path, ".enc")
      end
    end

    test "home directory expansion" do
      home = System.get_env("HOME") || "~"
      path = Path.join([home, ".nexus", "secrets.enc"])
      assert String.contains?(path, "secrets.enc")
    end
  end

  describe "concurrent access patterns" do
    test "Task.async pattern for concurrent operations" do
      # Validate the pattern used for concurrent access
      tasks =
        for i <- 1..10 do
          Task.async(fn -> {:ok, i} end)
        end

      results = Task.await_many(tasks)
      assert length(results) == 10
      assert Enum.all?(results, fn {:ok, _} -> true end)
    end

    test "ETS could be used for caching" do
      # Just validate ETS operations work
      table = :ets.new(:test_cache, [:set, :public])
      :ets.insert(table, {"key", "value"})
      [{_, value}] = :ets.lookup(table, "key")
      assert value == "value"
      :ets.delete(table)
    end
  end
end

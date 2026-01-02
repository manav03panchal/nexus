defmodule Nexus.Secrets.VaultTest do
  use ExUnit.Case, async: false

  alias Nexus.Secrets.Vault

  @moduletag :unit

  # Use a temporary directory for each test
  setup do
    # Create a unique temp directory for this test
    tmp_dir = Path.join(System.tmp_dir!(), "nexus_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    # Set up environment with test master key
    test_key = Vault.generate_key()
    encoded_key = Base.encode64(test_key)
    System.put_env("NEXUS_MASTER_KEY", encoded_key)

    # Override the secrets path
    secrets_path = Path.join(tmp_dir, "secrets.enc")

    on_exit(fn ->
      System.delete_env("NEXUS_MASTER_KEY")
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir, test_key: test_key, secrets_path: secrets_path}
  end

  describe "encrypt/2 and decrypt/2" do
    test "encrypts and decrypts data successfully" do
      key = Vault.generate_key()
      plaintext = "hello world"

      {:ok, ciphertext} = Vault.encrypt(plaintext, key)
      {:ok, decrypted} = Vault.decrypt(ciphertext, key)

      assert decrypted == plaintext
    end

    test "different IVs produce different ciphertexts" do
      key = Vault.generate_key()
      plaintext = "hello world"

      {:ok, ciphertext1} = Vault.encrypt(plaintext, key)
      {:ok, ciphertext2} = Vault.encrypt(plaintext, key)

      # Different IVs mean different ciphertexts
      assert ciphertext1 != ciphertext2

      # But both decrypt to the same plaintext
      {:ok, decrypted1} = Vault.decrypt(ciphertext1, key)
      {:ok, decrypted2} = Vault.decrypt(ciphertext2, key)

      assert decrypted1 == plaintext
      assert decrypted2 == plaintext
    end

    test "decryption fails with wrong key" do
      key1 = Vault.generate_key()
      key2 = Vault.generate_key()
      plaintext = "secret data"

      {:ok, ciphertext} = Vault.encrypt(plaintext, key1)
      result = Vault.decrypt(ciphertext, key2)

      assert result == {:error, :decryption_failed}
    end

    test "decryption fails with tampered ciphertext" do
      key = Vault.generate_key()
      plaintext = "secret data"

      {:ok, ciphertext} = Vault.encrypt(plaintext, key)

      # Tamper with the ciphertext (flip a bit in the middle)
      tampered =
        ciphertext
        |> :binary.bin_to_list()
        |> List.update_at(20, &Bitwise.bxor(&1, 1))
        |> :binary.list_to_bin()

      result = Vault.decrypt(tampered, key)

      assert result == {:error, :decryption_failed}
    end

    test "returns error for invalid key length" do
      short_key = <<1, 2, 3, 4, 5>>
      plaintext = "hello"

      result = Vault.encrypt(plaintext, short_key)

      assert result == {:error, :invalid_key_length}
    end

    test "returns error for invalid ciphertext" do
      key = Vault.generate_key()
      invalid_ciphertext = "too short"

      result = Vault.decrypt(invalid_ciphertext, key)

      assert result == {:error, :invalid_ciphertext}
    end

    test "handles empty plaintext" do
      key = Vault.generate_key()
      plaintext = ""

      {:ok, ciphertext} = Vault.encrypt(plaintext, key)
      {:ok, decrypted} = Vault.decrypt(ciphertext, key)

      assert decrypted == plaintext
    end

    test "handles binary data" do
      key = Vault.generate_key()
      binary_data = <<0, 1, 2, 255, 254, 253>>

      {:ok, ciphertext} = Vault.encrypt(binary_data, key)
      {:ok, decrypted} = Vault.decrypt(ciphertext, key)

      assert decrypted == binary_data
    end

    test "handles large plaintext" do
      key = Vault.generate_key()
      # 1MB of random data
      large_data = :crypto.strong_rand_bytes(1_000_000)

      {:ok, ciphertext} = Vault.encrypt(large_data, key)
      {:ok, decrypted} = Vault.decrypt(ciphertext, key)

      assert decrypted == large_data
    end
  end

  describe "derive_key/2" do
    test "derives consistent key from same passphrase and salt" do
      passphrase = "my secret passphrase"
      salt = Vault.generate_salt()

      key1 = Vault.derive_key(passphrase, salt)
      key2 = Vault.derive_key(passphrase, salt)

      assert key1 == key2
      assert byte_size(key1) == 32
    end

    test "different salts produce different keys" do
      passphrase = "my secret passphrase"
      salt1 = Vault.generate_salt()
      salt2 = Vault.generate_salt()

      key1 = Vault.derive_key(passphrase, salt1)
      key2 = Vault.derive_key(passphrase, salt2)

      assert key1 != key2
    end

    test "different passphrases produce different keys" do
      salt = Vault.generate_salt()
      key1 = Vault.derive_key("passphrase1", salt)
      key2 = Vault.derive_key("passphrase2", salt)

      assert key1 != key2
    end
  end

  describe "generate_key/0" do
    test "generates 32-byte key" do
      key = Vault.generate_key()

      assert byte_size(key) == 32
    end

    test "generates unique keys" do
      key1 = Vault.generate_key()
      key2 = Vault.generate_key()

      assert key1 != key2
    end
  end

  describe "generate_salt/0" do
    test "generates 16-byte salt" do
      salt = Vault.generate_salt()

      assert byte_size(salt) == 16
    end

    test "generates unique salts" do
      salt1 = Vault.generate_salt()
      salt2 = Vault.generate_salt()

      assert salt1 != salt2
    end
  end
end

defmodule Nexus.Secrets.CryptoPropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Nexus.Secrets.Vault

  @moduletag :property

  describe "encryption properties" do
    property "encrypt then decrypt is identity" do
      check all(
              plaintext <- binary(),
              max_runs: 100
            ) do
        key = Vault.generate_key()

        {:ok, ciphertext} = Vault.encrypt(plaintext, key)
        {:ok, decrypted} = Vault.decrypt(ciphertext, key)

        assert decrypted == plaintext
      end
    end

    property "ciphertext is always larger than plaintext" do
      check all(
              plaintext <- binary(),
              max_runs: 100
            ) do
        key = Vault.generate_key()

        {:ok, ciphertext} = Vault.encrypt(plaintext, key)

        # Ciphertext includes 12-byte IV + 16-byte tag + encrypted data
        # GCM doesn't add padding, so ciphertext body equals plaintext length
        expected_overhead = 12 + 16
        assert byte_size(ciphertext) == byte_size(plaintext) + expected_overhead
      end
    end

    property "same plaintext with same key produces different ciphertext" do
      check all(
              plaintext <- binary(min_length: 1),
              max_runs: 50
            ) do
        key = Vault.generate_key()

        {:ok, ciphertext1} = Vault.encrypt(plaintext, key)
        {:ok, ciphertext2} = Vault.encrypt(plaintext, key)

        # Different random IVs mean different ciphertexts
        assert ciphertext1 != ciphertext2
      end
    end

    property "decryption with wrong key always fails" do
      check all(
              plaintext <- binary(min_length: 1),
              max_runs: 50
            ) do
        key1 = Vault.generate_key()
        key2 = Vault.generate_key()

        {:ok, ciphertext} = Vault.encrypt(plaintext, key1)
        result = Vault.decrypt(ciphertext, key2)

        assert result == {:error, :decryption_failed}
      end
    end

    property "any bit flip in ciphertext causes decryption failure" do
      check all(
              plaintext <- binary(min_length: 10),
              bit_position <- integer(0..99),
              max_runs: 50
            ) do
        key = Vault.generate_key()

        {:ok, ciphertext} = Vault.encrypt(plaintext, key)

        # Flip a bit at a position within the ciphertext
        byte_pos = rem(bit_position, byte_size(ciphertext))

        tampered =
          ciphertext
          |> :binary.bin_to_list()
          |> List.update_at(byte_pos, &Bitwise.bxor(&1, 1))
          |> :binary.list_to_bin()

        result = Vault.decrypt(tampered, key)

        assert result == {:error, :decryption_failed}
      end
    end
  end

  describe "key derivation properties" do
    property "key derivation is deterministic" do
      check all(
              passphrase <- string(:printable, min_length: 1),
              max_runs: 50
            ) do
        salt = Vault.generate_salt()

        key1 = Vault.derive_key(passphrase, salt)
        key2 = Vault.derive_key(passphrase, salt)

        assert key1 == key2
      end
    end

    property "derived keys are always 32 bytes" do
      check all(
              passphrase <- string(:printable, min_length: 1),
              max_runs: 50
            ) do
        salt = Vault.generate_salt()
        key = Vault.derive_key(passphrase, salt)

        assert byte_size(key) == 32
      end
    end

    property "different salts produce different keys for same passphrase" do
      check all(
              passphrase <- string(:printable, min_length: 1),
              max_runs: 50
            ) do
        salt1 = Vault.generate_salt()
        salt2 = Vault.generate_salt()

        key1 = Vault.derive_key(passphrase, salt1)
        key2 = Vault.derive_key(passphrase, salt2)

        assert key1 != key2
      end
    end
  end

  describe "key generation properties" do
    property "generated keys are always 32 bytes" do
      check all(
              _ <- constant(nil),
              max_runs: 100
            ) do
        key = Vault.generate_key()
        assert byte_size(key) == 32
      end
    end

    property "generated keys are unique" do
      # Generate a batch of keys and verify they're all unique
      keys = for _ <- 1..100, do: Vault.generate_key()
      unique_keys = Enum.uniq(keys)

      assert length(keys) == length(unique_keys)
    end
  end
end

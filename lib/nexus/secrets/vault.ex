defmodule Nexus.Secrets.Vault do
  @moduledoc """
  Encrypted secrets storage using AES-256-GCM.

  Secrets are stored in ~/.nexus/secrets.enc as encrypted JSON.
  The master key is derived from a passphrase or key file using PBKDF2.

  ## Security

  - AES-256-GCM provides authenticated encryption
  - Unique 12-byte IV for each encryption operation
  - 16-byte authentication tag prevents tampering
  - PBKDF2-HMAC-SHA256 with 100k iterations for key derivation
  """

  alias Nexus.Secrets.Keyring

  @type secret_name :: String.t()
  @type secret_value :: String.t()

  @secrets_file "secrets.enc"
  @aes_key_length 32
  @iv_length 12
  @tag_length 16
  @pbkdf2_iterations 100_000

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Sets a secret value in the vault.

  ## Options

  - `:force` - Overwrite existing secret (default: false)

  ## Examples

      iex> Vault.set("api_key", "sk-1234567890")
      :ok

      iex> Vault.set("api_key", "new-value", force: true)
      :ok
  """
  @spec set(secret_name(), secret_value(), keyword()) :: :ok | {:error, term()}
  def set(name, value, opts \\ []) when is_binary(name) and is_binary(value) do
    force = Keyword.get(opts, :force, false)

    with {:ok, key} <- Keyring.get_master_key(),
         {:ok, secrets} <- load_secrets(key),
         :ok <- validate_overwrite(secrets, name, force) do
      updated_secrets = Map.put(secrets, name, value)
      save_secrets(updated_secrets, key)
    end
  end

  @doc """
  Retrieves a secret value from the vault.

  ## Examples

      iex> Vault.get("api_key")
      {:ok, "sk-1234567890"}

      iex> Vault.get("nonexistent")
      {:error, :not_found}
  """
  @spec get(secret_name()) :: {:ok, secret_value()} | {:error, term()}
  def get(name) when is_binary(name) do
    with {:ok, key} <- Keyring.get_master_key(),
         {:ok, secrets} <- load_secrets(key) do
      case Map.fetch(secrets, name) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :not_found}
      end
    end
  end

  @doc """
  Lists all secret names in the vault.

  ## Examples

      iex> Vault.list()
      {:ok, ["api_key", "db_password", "jwt_secret"]}
  """
  @spec list() :: {:ok, [secret_name()]} | {:error, term()}
  def list do
    with {:ok, key} <- Keyring.get_master_key(),
         {:ok, secrets} <- load_secrets(key) do
      {:ok, Map.keys(secrets) |> Enum.sort()}
    end
  end

  @doc """
  Deletes a secret from the vault.

  ## Examples

      iex> Vault.delete("api_key")
      :ok

      iex> Vault.delete("nonexistent")
      {:error, :not_found}
  """
  @spec delete(secret_name()) :: :ok | {:error, term()}
  def delete(name) when is_binary(name) do
    with {:ok, key} <- Keyring.get_master_key(),
         {:ok, secrets} <- load_secrets(key) do
      if Map.has_key?(secrets, name) do
        updated_secrets = Map.delete(secrets, name)
        save_secrets(updated_secrets, key)
      else
        {:error, :not_found}
      end
    end
  end

  @doc """
  Checks if the vault exists and can be decrypted.
  """
  @spec exists?() :: boolean()
  def exists? do
    case Keyring.get_master_key() do
      {:ok, key} ->
        case load_secrets(key) do
          {:ok, _} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  @doc """
  Initializes a new vault with an empty secrets store.
  """
  @spec init() :: :ok | {:error, term()}
  def init do
    with {:ok, key} <- Keyring.get_master_key() do
      if File.exists?(secrets_path()) do
        {:error, :already_exists}
      else
        save_secrets(%{}, key)
      end
    end
  end

  # ============================================================================
  # Encryption / Decryption
  # ============================================================================

  @doc """
  Encrypts data using AES-256-GCM.

  Returns `{iv, tag, ciphertext}` as a single binary.
  """
  @spec encrypt(binary(), binary()) :: {:ok, binary()} | {:error, term()}
  def encrypt(plaintext, key) when byte_size(key) == @aes_key_length do
    iv = :crypto.strong_rand_bytes(@iv_length)

    try do
      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          key,
          iv,
          plaintext,
          <<>>,
          @tag_length,
          true
        )

      # Format: IV (12 bytes) || Tag (16 bytes) || Ciphertext
      {:ok, iv <> tag <> ciphertext}
    rescue
      e -> {:error, {:encryption_failed, Exception.message(e)}}
    end
  end

  def encrypt(_, _), do: {:error, :invalid_key_length}

  @doc """
  Decrypts data encrypted with AES-256-GCM.

  Expects input format: `{iv, tag, ciphertext}` as a single binary.
  """
  @spec decrypt(binary(), binary()) :: {:ok, binary()} | {:error, term()}
  def decrypt(encrypted, key)
      when byte_size(key) == @aes_key_length and
             byte_size(encrypted) >= @iv_length + @tag_length do
    <<iv::binary-size(@iv_length), tag::binary-size(@tag_length), ciphertext::binary>> =
      encrypted

    try do
      case :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key,
             iv,
             ciphertext,
             <<>>,
             tag,
             false
           ) do
        plaintext when is_binary(plaintext) -> {:ok, plaintext}
        :error -> {:error, :decryption_failed}
      end
    rescue
      _ -> {:error, :decryption_failed}
    end
  end

  def decrypt(_, _), do: {:error, :invalid_ciphertext}

  # ============================================================================
  # Key Derivation
  # ============================================================================

  @doc """
  Derives a 256-bit key from a passphrase using PBKDF2-HMAC-SHA256.
  """
  @spec derive_key(String.t(), binary()) :: binary()
  def derive_key(passphrase, salt) when is_binary(passphrase) and is_binary(salt) do
    :crypto.pbkdf2_hmac(:sha256, passphrase, salt, @pbkdf2_iterations, @aes_key_length)
  end

  @doc """
  Generates a random 256-bit key.
  """
  @spec generate_key() :: binary()
  def generate_key do
    :crypto.strong_rand_bytes(@aes_key_length)
  end

  @doc """
  Generates a random salt for key derivation.
  """
  @spec generate_salt() :: binary()
  def generate_salt do
    :crypto.strong_rand_bytes(16)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp load_secrets(key) do
    path = secrets_path()

    if File.exists?(path) do
      with {:ok, encrypted} <- File.read(path),
           {:ok, decoded} <- Base.decode64(encrypted),
           {:ok, json} <- decrypt(decoded, key),
           {:ok, secrets} <- Jason.decode(json) do
        {:ok, secrets}
      else
        {:error, :invalid} -> {:error, :invalid_secrets_file}
        {:error, reason} -> {:error, reason}
        _ -> {:error, :decryption_failed}
      end
    else
      {:ok, %{}}
    end
  end

  defp save_secrets(secrets, key) do
    path = secrets_path()

    with {:ok, json} <- Jason.encode(secrets),
         {:ok, encrypted} <- encrypt(json, key) do
      encoded = Base.encode64(encrypted)

      # Ensure directory exists
      path |> Path.dirname() |> File.mkdir_p!()

      # Write with restricted permissions
      File.write!(path, encoded)
      File.chmod!(path, 0o600)

      :ok
    end
  end

  defp validate_overwrite(secrets, name, force) do
    if Map.has_key?(secrets, name) and not force do
      {:error, {:already_exists, name}}
    else
      :ok
    end
  end

  defp secrets_path do
    nexus_dir = Path.expand("~/.nexus")
    Path.join(nexus_dir, @secrets_file)
  end
end

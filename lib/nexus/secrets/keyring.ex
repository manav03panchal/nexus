defmodule Nexus.Secrets.Keyring do
  @moduledoc """
  Master key management for the secrets vault.

  Supports multiple key sources in priority order:
  1. Environment variable: `NEXUS_MASTER_KEY` (base64-encoded 32-byte key)
  2. Key file: `~/.nexus/master.key` (raw 32-byte key, chmod 600)
  3. Passphrase derivation: `NEXUS_PASSPHRASE` environment variable
  4. Interactive prompt (CLI only, when stdin is a TTY)

  ## Security

  - Key files must have mode 0600 (readable only by owner)
  - Environment variables are checked but not recommended for production
  - Passphrase derivation uses PBKDF2 with 100k iterations
  """

  import Bitwise

  alias Nexus.Secrets.Vault

  @key_file "master.key"
  @salt_file "master.salt"
  @key_length 32

  @type key_source :: :env | :env_passphrase | :file | :prompt

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Gets the master key from the highest priority available source.

  ## Options

  - `:allow_prompt` - Allow interactive passphrase prompt (default: true)

  ## Examples

      iex> Keyring.get_master_key()
      {:ok, <<...32 bytes...>>}

      iex> Keyring.get_master_key(allow_prompt: false)
      {:error, :no_key_available}
  """
  @spec get_master_key(keyword()) :: {:ok, binary()} | {:error, term()}
  def get_master_key(opts \\ []) do
    allow_prompt = Keyword.get(opts, :allow_prompt, true)

    sources =
      [:env, :env_passphrase, :file] ++
        if allow_prompt, do: [:prompt], else: []

    Enum.reduce_while(sources, {:error, :no_key_available}, fn source, acc ->
      case get_key_from_source(source) do
        {:ok, key} -> {:halt, {:ok, key}}
        {:error, _} -> {:cont, acc}
      end
    end)
  end

  @doc """
  Checks which key source is currently available.

  ## Examples

      iex> Keyring.available_source()
      {:ok, :file}

      iex> Keyring.available_source()
      {:error, :no_key_available}
  """
  @spec available_source() :: {:ok, key_source()} | {:error, :no_key_available}
  def available_source do
    sources = [:env, :env_passphrase, :file]

    Enum.reduce_while(sources, {:error, :no_key_available}, fn source, acc ->
      case get_key_from_source(source) do
        {:ok, _} -> {:halt, {:ok, source}}
        {:error, _} -> {:cont, acc}
      end
    end)
  end

  @doc """
  Generates and saves a new master key to the key file.

  Returns the generated key for backup purposes.
  """
  @spec generate_key_file() :: {:ok, binary()} | {:error, {:file_error, String.t()}}
  def generate_key_file do
    key = Vault.generate_key()
    path = key_file_path()

    try do
      # Ensure directory exists with proper permissions
      dir = Path.dirname(path)
      File.mkdir_p!(dir)
      File.chmod!(dir, 0o700)

      # Write key with restricted permissions
      File.write!(path, key)
      File.chmod!(path, 0o600)

      {:ok, key}
    rescue
      e in File.Error ->
        {:error, {:file_error, Exception.message(e)}}
    end
  end

  @doc """
  Initializes the keyring with a passphrase-derived key.

  Generates a salt and derives the key, storing the salt for future use.
  """
  @spec init_with_passphrase(String.t()) :: {:ok, binary()} | {:error, term()}
  def init_with_passphrase(passphrase)
      when is_binary(passphrase) and byte_size(passphrase) >= 8 do
    salt = Vault.generate_salt()
    key = Vault.derive_key(passphrase, salt)

    # Save salt for future key derivation
    salt_path = salt_file_path()
    dir = Path.dirname(salt_path)
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)

    File.write!(salt_path, Base.encode64(salt))
    File.chmod!(salt_path, 0o600)

    {:ok, key}
  end

  def init_with_passphrase(_), do: {:error, :passphrase_too_short}

  @doc """
  Checks if a key file exists.
  """
  @spec key_file_exists?() :: boolean()
  def key_file_exists? do
    File.exists?(key_file_path())
  end

  @doc """
  Validates the key file has correct permissions.
  """
  @spec validate_key_file_permissions() :: :ok | {:error, :insecure_permissions}
  def validate_key_file_permissions do
    path = key_file_path()

    cond do
      not File.exists?(path) ->
        :ok

      secure_permissions?(path) ->
        :ok

      true ->
        {:error, :insecure_permissions}
    end
  end

  defp secure_permissions?(path) do
    case File.stat(path) do
      {:ok, %{mode: mode}} ->
        # Check if mode is owner read/write only (0o600)
        (mode &&& 0o777) == 0o600

      {:error, _} ->
        false
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_key_from_source(:env) do
    case System.get_env("NEXUS_MASTER_KEY") do
      nil ->
        {:error, :not_set}

      encoded ->
        case Base.decode64(encoded) do
          {:ok, key} when byte_size(key) == @key_length -> {:ok, key}
          {:ok, _} -> {:error, :invalid_key_length}
          :error -> {:error, :invalid_base64}
        end
    end
  end

  defp get_key_from_source(:env_passphrase) do
    with passphrase when is_binary(passphrase) <- System.get_env("NEXUS_PASSPHRASE"),
         {:ok, salt} <- load_salt() do
      {:ok, Vault.derive_key(passphrase, salt)}
    else
      nil -> {:error, :not_set}
      error -> error
    end
  end

  defp get_key_from_source(:file) do
    path = key_file_path()

    with :ok <- validate_key_file_permissions(),
         {:ok, key} <- File.read(path) do
      if byte_size(key) == @key_length do
        {:ok, key}
      else
        {:error, :invalid_key_length}
      end
    else
      {:error, :enoent} -> {:error, :no_key_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_key_from_source(:prompt) do
    if interactive_terminal?() do
      prompt_for_passphrase()
    else
      {:error, :not_interactive}
    end
  end

  defp load_salt do
    path = salt_file_path()

    case File.read(path) do
      {:ok, encoded} ->
        case Base.decode64(String.trim(encoded)) do
          {:ok, salt} -> {:ok, salt}
          :error -> {:error, :invalid_salt}
        end

      {:error, :enoent} ->
        {:error, :no_salt_file}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prompt_for_passphrase do
    IO.write(:stderr, "Enter vault passphrase: ")

    # Read passphrase with echo disabled if possible
    result = :io.get_password()
    IO.write(:stderr, "\n")

    passphrase =
      case result do
        chars when is_list(chars) ->
          List.to_string(chars)

        binary when is_binary(binary) ->
          String.trim(binary)

        _ ->
          # Fallback to regular input
          IO.gets("") |> String.trim()
      end

    if byte_size(passphrase) >= 8 do
      case load_salt() do
        {:ok, salt} ->
          {:ok, Vault.derive_key(passphrase, salt)}

        {:error, :no_salt_file} ->
          # First time - generate salt
          salt = Vault.generate_salt()
          save_salt(salt)
          {:ok, Vault.derive_key(passphrase, salt)}

        error ->
          error
      end
    else
      {:error, :passphrase_too_short}
    end
  end

  defp save_salt(salt) do
    path = salt_file_path()
    dir = Path.dirname(path)
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    File.write!(path, Base.encode64(salt))
    File.chmod!(path, 0o600)
  end

  defp interactive_terminal? do
    # Check if we're running with an interactive stdin
    case :io.getopts(:standard_io) do
      opts when is_list(opts) -> Keyword.get(opts, :binary, false) == false
      _ -> false
    end
  end

  defp key_file_path do
    Path.expand("~/.nexus/#{@key_file}")
  end

  defp salt_file_path do
    Path.expand("~/.nexus/#{@salt_file}")
  end
end

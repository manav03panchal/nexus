defmodule Nexus.CLI.Secret do
  @moduledoc """
  Handles the `nexus secret` subcommand for managing encrypted secrets.

  ## Commands

  - `nexus secret set <name> [value]` - Set a secret (prompts if no value given)
  - `nexus secret get <name>` - Retrieve a secret value
  - `nexus secret list` - List all secret names
  - `nexus secret delete <name>` - Delete a secret
  - `nexus secret init` - Initialize the secrets vault

  ## Examples

      $ nexus secret init
      Vault initialized. Key saved to ~/.nexus/master.key
      IMPORTANT: Back up this key! If lost, secrets cannot be recovered.

      $ nexus secret set API_KEY sk-1234567890
      Secret 'API_KEY' saved.

      $ nexus secret list
      API_KEY
      DB_PASSWORD

      $ nexus secret get API_KEY
      sk-1234567890

      $ nexus secret delete API_KEY
      Secret 'API_KEY' deleted.
  """

  alias Nexus.Secrets.{Keyring, Vault}

  # ============================================================================
  # Command Handlers
  # ============================================================================

  @doc """
  Initializes the secrets vault with a new master key.
  """
  @spec execute_init(map()) :: {:ok, integer()} | {:error, integer()}
  def execute_init(_parsed) do
    if Keyring.key_file_exists?() do
      IO.puts(:stderr, "Error: Vault already initialized (~/.nexus/master.key exists)")
      IO.puts(:stderr, "Delete ~/.nexus/master.key to reinitialize (will lose all secrets!)")
      {:error, 1}
    else
      case Keyring.generate_key_file() do
        {:ok, key} ->
          key_b64 = Base.encode64(key)

          IO.puts("Vault initialized successfully!")
          IO.puts("")
          IO.puts("Master key saved to: ~/.nexus/master.key")
          IO.puts("")
          IO.puts("IMPORTANT: Back up your master key!")
          IO.puts("If lost, your secrets cannot be recovered.")
          IO.puts("")
          IO.puts("Base64 key (for backup):")
          IO.puts(key_b64)

          {:ok, 0}

        {:error, reason} ->
          IO.puts(:stderr, "Error initializing vault: #{format_error(reason)}")
          {:error, 1}
      end
    end
  end

  @doc """
  Sets a secret value.
  """
  @spec execute_set(map()) :: {:ok, integer()} | {:error, integer()}
  def execute_set(parsed) do
    name = parsed.args[:name]
    value = parsed.args[:value]
    force = parsed.flags[:force] || false

    # Prompt for value if not provided
    value =
      if is_nil(value) or value == "" do
        prompt_secret_value(name)
      else
        value
      end

    if is_nil(value) or value == "" do
      IO.puts(:stderr, "Error: Secret value cannot be empty")
      {:error, 1}
    else
      case Vault.set(name, value, force: force) do
        :ok ->
          IO.puts("Secret '#{name}' saved.")
          {:ok, 0}

        {:error, {:already_exists, _}} ->
          IO.puts(:stderr, "Error: Secret '#{name}' already exists. Use --force to overwrite.")
          {:error, 1}

        {:error, reason} ->
          IO.puts(:stderr, "Error: #{format_error(reason)}")
          {:error, 1}
      end
    end
  end

  @doc """
  Retrieves a secret value.
  """
  @spec execute_get(map()) :: {:ok, integer()} | {:error, integer()}
  def execute_get(parsed) do
    name = parsed.args[:name]

    case Vault.get(name) do
      {:ok, value} ->
        IO.puts(value)
        {:ok, 0}

      {:error, :not_found} ->
        IO.puts(:stderr, "Error: Secret '#{name}' not found")
        {:error, 1}

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{format_error(reason)}")
        {:error, 1}
    end
  end

  @doc """
  Lists all secret names.
  """
  @spec execute_list(map()) :: {:ok, integer()} | {:error, integer()}
  def execute_list(parsed) do
    format = parsed.options[:format] || :text

    case Vault.list() do
      {:ok, []} ->
        if format == :json do
          IO.puts("[]")
        else
          IO.puts("No secrets stored.")
        end

        {:ok, 0}

      {:ok, names} ->
        case format do
          :json ->
            IO.puts(Jason.encode!(names))

          :text ->
            Enum.each(names, &IO.puts/1)
        end

        {:ok, 0}

      {:error, :no_key_available} ->
        IO.puts(:stderr, "Error: No master key available. Run 'nexus secret init' first.")
        {:error, 1}

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{format_error(reason)}")
        {:error, 1}
    end
  end

  @doc """
  Deletes a secret.
  """
  @spec execute_delete(map()) :: {:ok, integer()} | {:error, integer()}
  def execute_delete(parsed) do
    name = parsed.args[:name]

    case Vault.delete(name) do
      :ok ->
        IO.puts("Secret '#{name}' deleted.")
        {:ok, 0}

      {:error, :not_found} ->
        IO.puts(:stderr, "Error: Secret '#{name}' not found")
        {:error, 1}

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{format_error(reason)}")
        {:error, 1}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp prompt_secret_value(name) do
    IO.write(:stderr, "Enter value for '#{name}': ")

    result = :io.get_password()
    IO.write(:stderr, "\n")

    case result do
      chars when is_list(chars) ->
        List.to_string(chars)

      binary when is_binary(binary) ->
        String.trim(binary)

      _ ->
        # Fallback to regular input
        IO.gets("") |> String.trim()
    end
  end

  defp format_error(:no_key_available) do
    "No master key available. Run 'nexus secret init' first."
  end

  defp format_error(:decryption_failed) do
    "Failed to decrypt secrets. Is the master key correct?"
  end

  defp format_error(:invalid_secrets_file) do
    "Secrets file is corrupted or invalid."
  end

  defp format_error(:insecure_permissions) do
    "Key file has insecure permissions. Run: chmod 600 ~/.nexus/master.key"
  end

  defp format_error({:already_exists, name}) do
    "Secret '#{name}' already exists. Use --force to overwrite."
  end

  defp format_error(reason) when is_atom(reason) do
    reason |> Atom.to_string() |> String.replace("_", " ")
  end

  defp format_error(reason), do: inspect(reason)
end

defmodule Nexus.SSH.KeyCallback do
  @moduledoc """
  SSH key callback module for loading specific key files.

  This module implements the `:ssh_client_key_api` behaviour to allow
  Nexus to use specific SSH key files rather than relying on the default
  key discovery in ~/.ssh.

  ## Usage

  Pass this module as the `:key_cb` option when connecting:

      SSH.connect(host, key_cb: {Nexus.SSH.KeyCallback, key_file: "/path/to/key"})

  """

  @behaviour :ssh_client_key_api

  @doc """
  Returns whether the given host/key should be accepted.

  Currently accepts all host keys (equivalent to StrictHostKeyChecking=no).
  In production, you may want to implement proper host key verification.
  """
  @impl true
  def is_host_key(_key, _host, _algorithm, _opts) do
    true
  end

  @doc """
  Returns the user's public/private key pair.

  Loads the key from the file specified in the `:key_file` option.
  """
  @impl true
  def user_key(algorithm, opts) do
    key_file = Keyword.get(opts, :key_file)

    if key_file do
      load_key_file(key_file, algorithm)
    else
      {:error, :no_key_file}
    end
  end

  @doc """
  Adds a host key to the known hosts.

  Currently a no-op - keys are not persisted.
  """
  @impl true
  def add_host_key(_host, _port, _key, _opts) do
    :ok
  end

  # Private functions

  defp load_key_file(path, algorithm) do
    case File.read(path) do
      {:ok, pem_data} ->
        decode_key(pem_data, algorithm)

      {:error, reason} ->
        {:error, {:key_file_error, path, reason}}
    end
  end

  defp decode_key(pem_data, algorithm) do
    # Try to decode the PEM file
    case :public_key.pem_decode(pem_data) do
      [entry | _] ->
        key = :public_key.pem_entry_decode(entry)
        validate_key_algorithm(key, algorithm)

      [] ->
        # Maybe it's an OpenSSH format key
        decode_openssh_key(pem_data, algorithm)
    end
  rescue
    _ ->
      {:error, :invalid_key_format}
  end

  defp decode_openssh_key(data, algorithm) do
    # Try OpenSSH format (ssh-ed25519, ssh-rsa, etc.)
    # Note: :ssh_file.decode returns tuples directly, not wrapped in a list
    case :ssh_file.decode(data, :openssh_key_v1) do
      [] ->
        {:error, :unsupported_key_format}

      {:error, _} ->
        {:error, :unsupported_key_format}

      key when is_tuple(key) ->
        validate_key_algorithm(key, algorithm)
    end
  rescue
    _ ->
      {:error, :unsupported_key_format}
  end

  defp validate_key_algorithm(key, algorithm) do
    key_type = key_algorithm(key)

    if key_type == algorithm or compatible_algorithm?(key_type, algorithm) do
      {:ok, key}
    else
      # Return the key anyway - let SSH negotiate
      {:ok, key}
    end
  end

  defp key_algorithm({:RSAPrivateKey, _, _, _, _, _, _, _, _, _, _}), do: :"ssh-rsa"
  defp key_algorithm({:ECPrivateKey, _, _, _, _}), do: :"ecdsa-sha2-nistp256"
  defp key_algorithm({:ed_pri, :ed25519, _, _}), do: :"ssh-ed25519"
  defp key_algorithm({:ed25519, _, _}), do: :"ssh-ed25519"
  defp key_algorithm(_), do: :unknown

  defp compatible_algorithm?(:"ssh-rsa", :"rsa-sha2-256"), do: true
  defp compatible_algorithm?(:"ssh-rsa", :"rsa-sha2-512"), do: true
  defp compatible_algorithm?(_, _), do: false
end

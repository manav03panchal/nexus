defmodule Nexus.Resources.Validators do
  @moduledoc """
  Validation helpers for resource attributes.

  Provides validation functions for common resource attributes like
  paths, permissions, names, and states.
  """

  @type validation_error :: {:error, String.t()}
  @type validation_result :: :ok | validation_error()

  @doc """
  Validates that a path is absolute (starts with /).

  ## Examples

      iex> validate_path("/etc/nginx")
      :ok

      iex> validate_path("relative/path")
      {:error, "path must be absolute, got: relative/path"}

  """
  @spec validate_path(String.t()) :: validation_result()
  def validate_path(path) when is_binary(path) do
    if String.starts_with?(path, "/") do
      :ok
    else
      {:error, "path must be absolute, got: #{path}"}
    end
  end

  def validate_path(nil), do: :ok

  @doc """
  Validates file/directory permission mode.

  Mode must be an integer between 0 and 0o7777 (4095 decimal).

  ## Examples

      iex> validate_mode(0o644)
      :ok

      iex> validate_mode(0o755)
      :ok

      iex> validate_mode(10000)
      {:error, "invalid mode: 10000 (must be 0-7777 octal)"}

  """
  @spec validate_mode(integer() | nil) :: validation_result()
  def validate_mode(nil), do: :ok

  def validate_mode(mode) when is_integer(mode) and mode >= 0 and mode <= 0o7777 do
    :ok
  end

  def validate_mode(mode) when is_integer(mode) do
    {:error, "invalid mode: #{mode} (must be 0-7777 octal)"}
  end

  @doc """
  Validates a resource name (package, service, user, group).

  Names must be non-empty strings containing only safe characters.

  ## Examples

      iex> validate_name("nginx")
      :ok

      iex> validate_name("")
      {:error, "name cannot be empty"}

      iex> validate_name("bad;name")
      {:error, "name contains invalid characters: bad;name"}

  """
  @spec validate_name(String.t() | nil) :: validation_result()
  def validate_name(nil), do: :ok

  def validate_name("") do
    {:error, "name cannot be empty"}
  end

  def validate_name(name) when is_binary(name) do
    if Regex.match?(~r/^[a-zA-Z0-9._+@-]+$/, name) do
      :ok
    else
      {:error, "name contains invalid characters: #{name}"}
    end
  end

  @doc """
  Validates a list of names.

  ## Examples

      iex> validate_names(["nginx", "curl"])
      :ok

      iex> validate_names(["good", "bad;name"])
      {:error, "name contains invalid characters: bad;name"}

  """
  @spec validate_names([String.t()]) :: validation_result()
  def validate_names(names) when is_list(names) do
    Enum.reduce_while(names, :ok, fn name, :ok ->
      case validate_name(name) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Validates a username follows system conventions.

  Usernames should start with a letter or underscore, followed by
  letters, digits, underscores, or hyphens.

  ## Examples

      iex> validate_username("deploy")
      :ok

      iex> validate_username("_nginx")
      :ok

      iex> validate_username("123user")
      {:error, "invalid username: 123user (must start with letter or underscore)"}

  """
  @spec validate_username(String.t() | nil) :: validation_result()
  def validate_username(nil), do: :ok

  def validate_username(username) when is_binary(username) do
    if Regex.match?(~r/^[a-z_][a-z0-9_-]*$/, username) do
      :ok
    else
      {:error, "invalid username: #{username} (must start with letter or underscore)"}
    end
  end

  @doc """
  Validates a group name follows system conventions.
  """
  @spec validate_groupname(String.t() | nil) :: validation_result()
  def validate_groupname(name), do: validate_username(name)

  @doc """
  Validates a UID/GID is within valid range.

  ## Examples

      iex> validate_id(1000)
      :ok

      iex> validate_id(-1)
      {:error, "invalid id: -1 (must be non-negative)"}

  """
  @spec validate_id(integer() | nil) :: validation_result()
  def validate_id(nil), do: :ok

  def validate_id(id) when is_integer(id) and id >= 0 do
    :ok
  end

  def validate_id(id) when is_integer(id) do
    {:error, "invalid id: #{id} (must be non-negative)"}
  end

  @doc """
  Validates a shell path.

  ## Examples

      iex> validate_shell("/bin/bash")
      :ok

      iex> validate_shell("bash")
      {:error, "shell must be absolute path, got: bash"}

  """
  @spec validate_shell(String.t() | nil) :: validation_result()
  def validate_shell(nil), do: :ok

  def validate_shell(shell) when is_binary(shell) do
    if String.starts_with?(shell, "/") do
      :ok
    else
      {:error, "shell must be absolute path, got: #{shell}"}
    end
  end

  @doc """
  Validates a state atom is one of the expected values.

  ## Examples

      iex> validate_state(:present, [:present, :absent])
      :ok

      iex> validate_state(:invalid, [:present, :absent])
      {:error, "invalid state: invalid (expected one of: present, absent)"}

  """
  @spec validate_state(atom(), [atom()]) :: validation_result()
  def validate_state(state, valid_states) when is_atom(state) and is_list(valid_states) do
    if state in valid_states do
      :ok
    else
      expected = Enum.map_join(valid_states, ", ", &to_string/1)
      {:error, "invalid state: #{state} (expected one of: #{expected})"}
    end
  end

  @doc """
  Runs multiple validations and returns the first error, or :ok.

  ## Examples

      iex> validate_all([
      ...>   fn -> validate_path("/etc/nginx") end,
      ...>   fn -> validate_mode(0o644) end
      ...> ])
      :ok

  """
  @spec validate_all([(-> validation_result())]) :: validation_result()
  def validate_all(validations) when is_list(validations) do
    Enum.reduce_while(validations, :ok, fn validation, :ok ->
      case validation.() do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end

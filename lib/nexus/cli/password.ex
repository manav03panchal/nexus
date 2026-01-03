defmodule Nexus.CLI.Password do
  @moduledoc """
  Secure password prompting for CLI interactions.

  Provides functions to prompt for passwords without echoing them to the
  terminal. Works on Unix-like systems by manipulating terminal settings.

  ## Usage

      password = Nexus.CLI.Password.prompt("SSH Password: ")

  """

  @doc """
  Prompts for a password without echoing input.

  Returns the entered password as a string, or `nil` if the user
  cancels (Ctrl+C) or an error occurs.

  ## Options

    * `:confirm` - If true, asks for password twice and verifies match
    * `:min_length` - Minimum password length (default: 0)

  ## Examples

      iex> Password.prompt("Enter password: ")
      "secret123"

      iex> Password.prompt("New password: ", confirm: true)
      "newpassword"

  """
  @spec prompt(String.t(), keyword()) :: String.t() | nil
  def prompt(message, opts \\ []) do
    confirm = Keyword.get(opts, :confirm, false)
    min_length = Keyword.get(opts, :min_length, 0)

    case read_password(message) do
      nil ->
        nil

      password when byte_size(password) < min_length ->
        IO.puts("\nPassword must be at least #{min_length} characters.")
        prompt(message, opts)

      password ->
        if confirm do
          confirm_password(password, message)
        else
          password
        end
    end
  end

  @doc """
  Prompts for a password for a specific host.

  Includes the hostname in the prompt for clarity when connecting
  to multiple hosts.
  """
  @spec prompt_for_host(String.t(), String.t() | nil) :: String.t() | nil
  def prompt_for_host(hostname, username \\ nil) do
    prompt_text =
      if username do
        "Password for #{username}@#{hostname}: "
      else
        "Password for #{hostname}: "
      end

    prompt(prompt_text)
  end

  @doc """
  Prompts for sudo password.

  Includes a note that this is for privilege escalation.
  """
  @spec prompt_sudo(String.t() | nil) :: String.t() | nil
  def prompt_sudo(username \\ nil) do
    prompt_text =
      if username do
        "[sudo] password for #{username}: "
      else
        "[sudo] password: "
      end

    prompt(prompt_text)
  end

  # Private functions

  defp read_password(message) do
    # Print prompt without newline
    IO.write(message)

    # Disable echo
    case disable_echo() do
      :ok ->
        try do
          password = IO.gets("") |> handle_input()
          # Print newline after hidden input
          IO.puts("")
          password
        after
          # Always re-enable echo
          enable_echo()
        end

      {:error, _reason} ->
        # Fallback for non-TTY environments (piped input, etc.)
        IO.gets("") |> handle_input()
    end
  end

  defp handle_input(:eof), do: nil
  defp handle_input({:error, _}), do: nil
  defp handle_input(input) when is_binary(input), do: String.trim(input)

  defp confirm_password(password, message) do
    confirm_message = String.replace(message, ~r/:\s*$/, " (confirm): ")

    case read_password(confirm_message) do
      ^password ->
        password

      nil ->
        nil

      _mismatch ->
        IO.puts("Passwords do not match. Please try again.\n")
        prompt(message, confirm: true)
    end
  end

  defp disable_echo do
    # Use stty to disable echo on Unix systems
    case System.cmd("stty", ["-echo"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {error, _} -> {:error, error}
    end
  rescue
    _ -> {:error, :stty_not_available}
  end

  defp enable_echo do
    System.cmd("stty", ["echo"], stderr_to_stdout: true)
    :ok
  rescue
    _ -> :ok
  end
end

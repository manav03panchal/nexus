defmodule Nexus.DockerSSH do
  @moduledoc """
  Helper module for managing Docker SSH containers in integration tests.
  """

  @default_host "localhost"
  @default_port 2232
  @default_user "testuser"
  @default_password "testpass"

  @doc """
  Returns SSH connection options from environment or defaults.
  """
  def connection_opts do
    [
      host: System.get_env("SSH_TEST_HOST", @default_host),
      port: String.to_integer(System.get_env("SSH_TEST_PORT", "#{@default_port}")),
      user: System.get_env("SSH_TEST_USER", @default_user),
      password: System.get_env("SSH_TEST_PASSWORD", @default_password)
    ]
  end

  @doc """
  Checks if Docker SSH server is available.
  """
  def available? do
    opts = connection_opts()
    host = String.to_charlist(opts[:host])
    port = opts[:port]

    case :gen_tcp.connect(host, port, [], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end
end

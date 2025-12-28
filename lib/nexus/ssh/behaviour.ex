defmodule Nexus.SSH.Behaviour do
  @moduledoc """
  Behaviour for SSH operations.

  This behaviour defines the contract for SSH implementations,
  allowing for easy mocking in tests.
  """

  @type host :: String.t()
  @type conn :: term()
  @type command :: String.t()
  @type output :: String.t()
  @type exit_code :: non_neg_integer()
  @type opts :: keyword()

  @callback connect(host(), opts()) :: {:ok, conn()} | {:error, term()}
  @callback exec(conn(), command(), opts()) :: {:ok, output(), exit_code()} | {:error, term()}
  @callback close(conn()) :: :ok
end

defmodule Nexus.Types.WaitFor do
  @moduledoc """
  Represents a health check wait command.

  Used after deployments to verify services are healthy before
  proceeding to the next batch of hosts.
  """

  @type check_type :: :http | :tcp | :command

  @type t :: %__MODULE__{
          type: check_type(),
          target: String.t(),
          timeout: pos_integer(),
          interval: pos_integer(),
          expected_status: pos_integer() | nil,
          expected_body: String.t() | Regex.t() | nil
        }

  @enforce_keys [:type, :target]
  defstruct [
    :type,
    :target,
    :expected_status,
    :expected_body,
    timeout: 60_000,
    interval: 5_000
  ]

  @doc """
  Creates a new WaitFor health check command.

  ## Types

    * `:http` - HTTP GET request, checks for 2xx status
    * `:tcp` - TCP connection check
    * `:command` - Shell command, checks for exit code 0

  ## Options

    * `:timeout` - Total time to wait in milliseconds (default: 60_000)
    * `:interval` - Time between checks in milliseconds (default: 5_000)
    * `:expected_status` - Expected HTTP status code (default: 200)
    * `:expected_body` - Expected response body pattern (string or regex)

  ## Examples

      iex> WaitFor.new(:http, "http://localhost:4000/health")
      %WaitFor{type: :http, target: "http://localhost:4000/health"}

      iex> WaitFor.new(:tcp, "localhost:5432", timeout: 30_000)
      %WaitFor{type: :tcp, target: "localhost:5432", timeout: 30_000}

      iex> WaitFor.new(:command, "systemctl is-active app")
      %WaitFor{type: :command, target: "systemctl is-active app"}

  """
  @spec new(check_type(), String.t(), keyword()) :: t()
  def new(type, target, opts \\ [])
      when type in [:http, :tcp, :command] and is_binary(target) do
    %__MODULE__{
      type: type,
      target: target,
      timeout: Keyword.get(opts, :timeout, 60_000),
      interval: Keyword.get(opts, :interval, 5_000),
      expected_status: Keyword.get(opts, :expected_status),
      expected_body: Keyword.get(opts, :expected_body)
    }
  end
end

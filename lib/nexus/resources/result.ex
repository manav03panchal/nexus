defmodule Nexus.Resources.Result do
  @moduledoc """
  Result structure for resource operations.

  Captures the outcome of a resource execution including:
  - Status (ok, changed, failed, skipped)
  - Diff showing before/after state
  - Timing information
  - Handler notifications

  ## Status Values

    * `:ok` - Resource already in desired state, no changes made
    * `:changed` - Resource was modified to reach desired state
    * `:failed` - Resource operation failed
    * `:skipped` - Resource was skipped (condition not met, check mode, etc.)

  ## Examples

      # Resource already in desired state
      Result.ok("package[nginx]")

      # Resource was changed
      Result.changed("package[nginx]", %{
        before: %{installed: false},
        after: %{installed: true},
        changes: ["install package"]
      })

      # Resource failed
      Result.failed("package[nginx]", "apt-get returned exit code 100")

      # Resource skipped due to condition
      Result.skipped("package[nginx]", "condition not met")

  """

  @type status :: :ok | :changed | :failed | :skipped

  @type diff :: map()

  @type t :: %__MODULE__{
          resource: String.t(),
          status: status(),
          diff: diff() | nil,
          message: String.t() | nil,
          duration_ms: non_neg_integer(),
          notify: atom() | nil
        }

  @enforce_keys [:resource, :status]
  defstruct [
    :resource,
    :status,
    :diff,
    :message,
    :notify,
    duration_ms: 0
  ]

  @doc """
  Creates an :ok result (no changes needed).

  ## Options

    * `:message` - Optional status message
    * `:duration_ms` - Execution time in milliseconds

  """
  @spec ok(String.t(), keyword()) :: t()
  def ok(resource, opts \\ []) do
    %__MODULE__{
      resource: resource,
      status: :ok,
      message: Keyword.get(opts, :message),
      duration_ms: Keyword.get(opts, :duration_ms, 0)
    }
  end

  @doc """
  Creates a :changed result (resource was modified).

  ## Options

    * `:message` - Optional status message
    * `:notify` - Handler to trigger
    * `:duration_ms` - Execution time in milliseconds

  """
  @spec changed(String.t(), diff(), keyword()) :: t()
  def changed(resource, diff, opts \\ []) do
    %__MODULE__{
      resource: resource,
      status: :changed,
      diff: diff,
      message: Keyword.get(opts, :message),
      notify: Keyword.get(opts, :notify),
      duration_ms: Keyword.get(opts, :duration_ms, 0)
    }
  end

  @doc """
  Creates a :failed result (operation failed).

  ## Options

    * `:duration_ms` - Execution time in milliseconds
    * `:diff` - Partial diff if available

  """
  @spec failed(String.t(), String.t(), keyword()) :: t()
  def failed(resource, message, opts \\ []) do
    %__MODULE__{
      resource: resource,
      status: :failed,
      message: message,
      diff: Keyword.get(opts, :diff),
      duration_ms: Keyword.get(opts, :duration_ms, 0)
    }
  end

  @doc """
  Creates a :skipped result (resource not executed).

  Common reasons:
  - Condition not met (when: clause)
  - Check mode
  - Dependency failed

  """
  @spec skipped(String.t(), String.t()) :: t()
  def skipped(resource, reason) do
    %__MODULE__{
      resource: resource,
      status: :skipped,
      message: reason,
      duration_ms: 0
    }
  end

  @doc """
  Returns true if the result indicates changes were made.
  """
  @spec changed?(t()) :: boolean()
  def changed?(%__MODULE__{status: :changed}), do: true
  def changed?(%__MODULE__{}), do: false

  @doc """
  Returns true if the result indicates success (ok or changed).
  """
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{status: status}) when status in [:ok, :changed], do: true
  def success?(%__MODULE__{}), do: false

  @doc """
  Returns true if the result indicates failure.
  """
  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{status: :failed}), do: true
  def failed?(%__MODULE__{}), do: false
end

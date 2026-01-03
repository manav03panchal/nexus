defmodule Nexus.Resources.Resource do
  @moduledoc """
  Behaviour that all resource providers must implement.

  Resources follow a check-before-apply pattern for idempotency:
  1. `check/3` - Determine current state on the target host
  2. `diff/2` - Compare current state with desired state
  3. `apply/3` - Apply changes only if needed

  ## Provider Selection

  Resources use the `provider_for/1` callback to select the appropriate
  platform-specific implementation based on system facts (os_family, os, etc.).

  ## Example Provider

      defmodule Nexus.Resources.Providers.Package.Apt do
        @behaviour Nexus.Resources.Resource

        @impl true
        def check(%Package{name: name}, conn, _context) do
          # Check if package is installed via dpkg
        end

        @impl true
        def diff(resource, current_state) do
          # Compare installed vs desired state
        end

        @impl true
        def apply(resource, conn, context) do
          # Run apt-get install/remove
        end
      end

  """

  alias Nexus.Resources.Result

  @type conn :: pid() | nil
  @type context :: %{
          facts: map(),
          host_id: atom(),
          check_mode: boolean()
        }
  @type resource :: struct()
  @type current_state :: map()
  @type diff_result :: %{
          changed: boolean(),
          before: map(),
          after: map(),
          changes: [String.t()]
        }

  @doc """
  Checks the current state of the resource on the target host.

  Returns a map describing the current state that can be compared
  against the desired state defined in the resource struct.

  ## Parameters

    * `resource` - The resource struct with desired state
    * `conn` - SSH connection pid (nil for local execution)
    * `context` - Execution context with facts and options

  ## Returns

    * `{:ok, current_state}` - Map of current state values
    * `{:error, reason}` - If check failed

  """
  @callback check(resource(), conn(), context()) ::
              {:ok, current_state()} | {:error, term()}

  @doc """
  Compares current state with desired state and returns a diff.

  The diff includes what would change if `apply/3` were called.
  This is used for:
  - Determining if changes are needed
  - Displaying diff output to user
  - Check mode preview

  ## Parameters

    * `resource` - The resource struct with desired state
    * `current_state` - Map returned by `check/3`

  ## Returns

  A map with:
    * `:changed` - Boolean indicating if changes are needed
    * `:before` - Map of current state values
    * `:after` - Map of desired state values
    * `:changes` - List of human-readable change descriptions

  """
  @callback diff(resource(), current_state()) :: diff_result()

  @doc """
  Applies the resource to achieve the desired state.

  Should only make changes if `diff/2` indicated changes are needed.
  The executor handles checking the diff before calling apply.

  ## Parameters

    * `resource` - The resource struct with desired state
    * `conn` - SSH connection pid (nil for local execution)
    * `context` - Execution context with facts and options

  ## Returns

    * `{:ok, Result.t()}` - Success with result details
    * `{:error, reason}` - If apply failed

  """
  @callback apply(resource(), conn(), context()) ::
              {:ok, Result.t()} | {:error, term()}

  @doc """
  Returns the provider module to use based on system facts.

  For example, Package resource returns Apt for Debian, Yum for RHEL.
  This is called by the executor to select the right implementation.

  ## Parameters

    * `facts` - Map of system facts (os, os_family, arch, etc.)

  ## Returns

    * `{:ok, module}` - The provider module to use
    * `{:error, {:unsupported_os, os_family}}` - If no provider for this OS

  """
  @callback provider_for(map()) :: {:ok, module()} | {:error, term()}

  @doc """
  Returns a human-readable description of the resource for output.

  ## Example

      "package[nginx]"
      "service[nginx] state=running"
      "file[/etc/nginx/nginx.conf]"

  """
  @callback describe(resource()) :: String.t()

  @optional_callbacks [provider_for: 1]
end

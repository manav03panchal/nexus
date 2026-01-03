defmodule Nexus.Resources.Executor do
  @moduledoc """
  Executes resources with idempotency checks and diff output.

  The executor coordinates the check-diff-apply flow for resources:
  1. Evaluate `when:` condition
  2. Select provider based on OS facts
  3. Check current state via provider
  4. Compute diff between current and desired state
  5. If changed (and not check mode): apply changes
  6. Queue handler if `notify:` specified and changed
  7. Return result with diff

  ## Usage

      context = %{facts: %{os_family: :debian}, host_id: :web1, check_mode: false}

      {:ok, result} = Executor.execute(package_resource, ssh_conn, context)

  """

  alias Nexus.Conditions.Evaluator
  alias Nexus.Resources.{HandlerQueue, Result}
  alias Nexus.Resources.Providers
  alias Nexus.Resources.Types.{Command, Directory, File, Group, Package, Service, User}

  @resource_providers %{
    Package => Providers.Package,
    Service => Providers.Service,
    File => Providers.File,
    Directory => Providers.Directory,
    User => Providers.User,
    Group => Providers.Group,
    Command => Providers.Command
  }

  @doc """
  Executes a single resource, returning a Result.

  ## Parameters

    * `resource` - The resource struct to execute
    * `conn` - SSH connection pid (nil for local execution)
    * `context` - Execution context with facts and options

  ## Returns

    * `{:ok, Result.t()}` - Always returns ok with a Result struct
      - Result.status may be :ok, :changed, :failed, or :skipped

  """
  @spec execute(struct(), pid() | nil, map()) :: {:ok, Result.t()}
  def execute(resource, conn, context) do
    start_time = System.monotonic_time(:millisecond)

    # Check when: condition first
    condition = get_condition(resource)

    if Evaluator.evaluate(condition, context) do
      do_execute(resource, conn, context, start_time)
    else
      {:ok, Result.skipped(describe(resource), "condition not met")}
    end
  end

  defp do_execute(resource, conn, context, start_time) do
    resource_type = resource.__struct__
    provider_selector = Map.get(@resource_providers, resource_type)

    if provider_selector do
      execute_with_provider(resource, conn, context, provider_selector, start_time)
    else
      duration = System.monotonic_time(:millisecond) - start_time
      {:ok, Result.failed(describe(resource), "unknown resource type", duration_ms: duration)}
    end
  end

  defp execute_with_provider(resource, conn, context, provider_selector, start_time) do
    case provider_selector.provider_for(context.facts) do
      {:ok, provider} ->
        execute_resource(resource, conn, context, provider, start_time)

      {:error, {:unsupported_os, os}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        {:ok, Result.failed(describe(resource), "unsupported OS: #{os}", duration_ms: duration)}

      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start_time
        {:ok, Result.failed(describe(resource), inspect(reason), duration_ms: duration)}
    end
  end

  defp execute_resource(resource, conn, context, provider, start_time) do
    # Step 1: Check current state
    case provider.check(resource, conn, context) do
      {:ok, current_state} ->
        # Step 2: Compute diff
        diff = provider.diff(resource, current_state)

        if diff.changed do
          execute_change(resource, conn, context, provider, diff, start_time)
        else
          # No changes needed
          duration = System.monotonic_time(:millisecond) - start_time
          {:ok, Result.ok(describe(resource), duration_ms: duration)}
        end

      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start_time

        {:ok,
         Result.failed(describe(resource), "check failed: #{inspect(reason)}",
           duration_ms: duration
         )}
    end
  end

  defp execute_change(resource, conn, context, provider, diff, start_time) do
    if Map.get(context, :check_mode, false) do
      report_check_mode_change(resource, diff, start_time)
    else
      apply_change(resource, conn, context, provider, diff, start_time)
    end
  end

  defp report_check_mode_change(resource, diff, start_time) do
    duration = System.monotonic_time(:millisecond) - start_time

    {:ok,
     Result.changed(describe(resource), diff,
       message: "would change",
       notify: get_notify(resource),
       duration_ms: duration
     )}
  end

  defp apply_change(resource, conn, context, provider, diff, start_time) do
    case provider.apply(resource, conn, context) do
      {:ok, result} ->
        maybe_queue_handler(resource, result)
        {:ok, %{result | diff: diff}}

      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start_time
        {:ok, Result.failed(describe(resource), inspect(reason), duration_ms: duration)}
    end
  end

  defp maybe_queue_handler(resource, result) do
    notify = get_notify(resource)

    if notify && Result.changed?(result) do
      HandlerQueue.enqueue(notify)
    end
  end

  @doc """
  Executes multiple resources in sequence.

  Returns results for all resources. Stops on first failure unless
  continue_on_error is true.
  """
  @spec execute_all([struct()], pid() | nil, map(), keyword()) :: {:ok, [Result.t()]}
  def execute_all(resources, conn, context, opts \\ []) do
    continue_on_error = Keyword.get(opts, :continue_on_error, false)

    {results, _} =
      Enum.reduce_while(resources, {[], :continue}, fn resource, {acc, _} ->
        {:ok, result} = execute(resource, conn, context)

        if Result.failed?(result) and not continue_on_error do
          {:halt, {[result | acc], :stopped}}
        else
          {:cont, {[result | acc], :continue}}
        end
      end)

    {:ok, Enum.reverse(results)}
  end

  # Helpers to extract fields from different resource types

  defp get_condition(%Package{when: condition}), do: condition
  defp get_condition(%Service{when: condition}), do: condition
  defp get_condition(%File{when: condition}), do: condition
  defp get_condition(%Directory{when: condition}), do: condition
  defp get_condition(%User{when: condition}), do: condition
  defp get_condition(%Group{when: condition}), do: condition
  defp get_condition(%Command{when: condition}), do: condition
  defp get_condition(_), do: true

  defp get_notify(%Package{notify: notify}), do: notify
  defp get_notify(%Service{notify: notify}), do: notify
  defp get_notify(%File{notify: notify}), do: notify
  defp get_notify(%Directory{notify: notify}), do: notify
  defp get_notify(%User{notify: notify}), do: notify
  defp get_notify(%Group{notify: notify}), do: notify
  defp get_notify(%Command{notify: notify}), do: notify
  defp get_notify(_), do: nil

  defp describe(%Package{} = r), do: Package.describe(r)
  defp describe(%Service{} = r), do: Service.describe(r)
  defp describe(%File{} = r), do: File.describe(r)
  defp describe(%Directory{} = r), do: Directory.describe(r)
  defp describe(%User{} = r), do: User.describe(r)
  defp describe(%Group{} = r), do: Group.describe(r)
  defp describe(%Command{} = r), do: Command.describe(r)
  defp describe(r), do: inspect(r)
end

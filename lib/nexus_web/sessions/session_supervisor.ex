defmodule NexusWeb.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for managing execution sessions.

  Each execution session runs as a separate process, allowing
  concurrent pipeline executions with isolated state.
  """

  @doc """
  Starts a new execution session.

  ## Options

    * `:subscriber` - PID to receive status updates (optional)
    * `:check_mode` - Run in check mode without executing (default: false)
    * `:tags` - Only run tasks with these tags
    * `:skip_tags` - Skip tasks with these tags

  Returns `{:ok, session_id}` or `{:error, reason}`.
  """
  def start_session(config_file, task_name, opts \\ []) do
    session_id = generate_session_id()

    child_spec = %{
      id: session_id,
      start:
        {NexusWeb.ExecutionSession, :start_link,
         [
           [
             id: session_id,
             config_file: config_file,
             task: task_name,
             subscriber: Keyword.get(opts, :subscriber),
             check_mode: Keyword.get(opts, :check_mode, false),
             tags: Keyword.get(opts, :tags, []),
             skip_tags: Keyword.get(opts, :skip_tags, [])
           ]
         ]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(NexusWeb.SessionSupervisor, child_spec) do
      {:ok, _pid} -> {:ok, session_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all active sessions.
  """
  def list_sessions do
    DynamicSupervisor.which_children(NexusWeb.SessionSupervisor)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&is_pid/1)
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end

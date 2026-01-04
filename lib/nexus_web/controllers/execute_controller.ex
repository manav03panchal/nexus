defmodule NexusWeb.ExecuteController do
  @moduledoc """
  API endpoint to trigger task execution.
  """

  use NexusWeb, :controller

  def create(conn, %{"task" => task_name} = params) do
    config_file = Application.get_env(:nexus, :web_config_file)

    if is_nil(config_file) do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "No configuration file loaded"})
    else
      opts = [
        check_mode: Map.get(params, "check_mode", false),
        tags: Map.get(params, "tags", []),
        skip_tags: Map.get(params, "skip_tags", [])
      ]

      case NexusWeb.SessionSupervisor.start_session(config_file, task_name, opts) do
        {:ok, session_id} ->
          conn
          |> put_status(:accepted)
          |> json(%{
            session_id: session_id,
            status: "started",
            task: task_name
          })

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to start execution", reason: inspect(reason)})
      end
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: task"})
  end
end

defmodule NexusWeb.ConfigController do
  @moduledoc """
  API endpoint to retrieve the current nexus configuration.
  """

  use NexusWeb, :controller

  alias Nexus.DSL.Parser

  def show(conn, _params) do
    case Application.get_env(:nexus, :web_config_file) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "No configuration file loaded"})

      config_file ->
        case Parser.parse_file(config_file) do
          {:ok, config} ->
            json(conn, %{
              file: config_file,
              tasks: Enum.map(config.tasks, &task_to_json/1),
              hosts: Enum.map(config.hosts, &host_to_json/1)
            })

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to parse config", reason: inspect(reason)})
        end
    end
  end

  defp task_to_json(task) do
    %{
      name: task.name,
      description: Map.get(task, :description),
      hosts: Map.get(task, :hosts, []),
      depends_on: Map.get(task, :depends_on, []),
      tags: Map.get(task, :tags, [])
    }
  end

  defp host_to_json(host) do
    %{
      name: host.name,
      hostname: host.hostname,
      user: host.user
    }
  end
end

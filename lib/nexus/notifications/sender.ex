defmodule Nexus.Notifications.Sender do
  @moduledoc """
  Sends notifications via webhooks after pipeline completion.

  Supports multiple notification formats including Slack, Discord,
  Microsoft Teams, and generic JSON webhooks.
  """

  require Logger

  alias Nexus.Notifications.Templates
  alias Nexus.Types.Notification

  @type pipeline_result :: %{
          status: :success | :failure,
          duration_ms: non_neg_integer(),
          started_at: DateTime.t(),
          finished_at: DateTime.t(),
          tasks: [task_result()]
        }

  @type task_result :: %{
          name: atom(),
          status: :success | :failure | :skipped,
          hosts: [host_result()]
        }

  @type host_result :: %{
          host: String.t(),
          status: :success | :failure,
          output: String.t() | nil,
          error: String.t() | nil
        }

  @doc """
  Sends notifications for a pipeline result.

  Takes a list of Notification configs and sends to each that matches
  the result status.
  """
  @spec send_all([Notification.t()], pipeline_result()) :: :ok
  def send_all(notifications, result) when is_list(notifications) do
    notifications
    |> Enum.filter(&Notification.should_send?(&1, result.status))
    |> Enum.each(&send_notification(&1, result))

    :ok
  end

  @doc """
  Sends a single notification.
  """
  @spec send_notification(Notification.t(), pipeline_result()) :: :ok | {:error, term()}
  def send_notification(%Notification{} = notification, result) do
    payload = build_payload(notification.template, result)
    headers = Map.to_list(notification.headers)

    case Req.post(notification.url, json: payload, headers: headers) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.debug("Notification sent to #{notification.url}")
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Notification failed: HTTP #{status} - #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.warning("Notification failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Builds the notification payload for the given template.
  """
  @spec build_payload(atom(), pipeline_result()) :: map()
  def build_payload(:slack, result), do: Templates.slack(normalize_result(result))
  def build_payload(:discord, result), do: Templates.discord(normalize_result(result))
  def build_payload(:teams, result), do: Templates.teams(normalize_result(result))
  def build_payload(:generic, result), do: Templates.generic(normalize_result(result))
  def build_payload(_, result), do: Templates.generic(normalize_result(result))

  # Ensures result has all required fields for templates
  defp normalize_result(result) do
    now = DateTime.utc_now()

    %{
      status: Map.get(result, :status, :success),
      duration_ms: Map.get(result, :duration_ms, 0),
      started_at: Map.get(result, :started_at, now),
      finished_at: Map.get(result, :finished_at, now),
      tasks: Map.get(result, :tasks, [])
    }
  end
end

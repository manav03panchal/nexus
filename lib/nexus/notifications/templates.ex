defmodule Nexus.Notifications.Templates do
  @moduledoc """
  Notification message templates for various webhook services.

  Provides formatted payloads for Slack, Discord, Microsoft Teams,
  and generic webhooks based on pipeline execution results.
  """

  @type pipeline_result :: %{
          status: :success | :failure | :partial,
          tasks: [task_result()],
          duration_ms: non_neg_integer(),
          started_at: DateTime.t(),
          finished_at: DateTime.t()
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
  Generates a Slack Block Kit formatted message payload.
  """
  @spec slack(pipeline_result()) :: map()
  def slack(result) do
    %{
      blocks: [
        %{
          type: "header",
          text: %{
            type: "plain_text",
            text: slack_header(result.status),
            emoji: true
          }
        },
        %{
          type: "section",
          fields: [
            %{
              type: "mrkdwn",
              text: "*Status:*\n#{status_emoji(result.status)} #{status_text(result.status)}"
            },
            %{
              type: "mrkdwn",
              text: "*Duration:*\n#{format_duration(result.duration_ms)}"
            }
          ]
        },
        %{
          type: "section",
          fields: [
            %{
              type: "mrkdwn",
              text: "*Started:*\n#{format_time(result.started_at)}"
            },
            %{
              type: "mrkdwn",
              text: "*Finished:*\n#{format_time(result.finished_at)}"
            }
          ]
        },
        %{
          type: "divider"
        },
        %{
          type: "section",
          text: %{
            type: "mrkdwn",
            text: slack_task_summary(result.tasks)
          }
        }
      ]
    }
  end

  @doc """
  Generates a Discord embed formatted message payload.
  """
  @spec discord(pipeline_result()) :: map()
  def discord(result) do
    %{
      embeds: [
        %{
          title: discord_title(result.status),
          color: discord_color(result.status),
          fields: [
            %{
              name: "Status",
              value: status_text(result.status),
              inline: true
            },
            %{
              name: "Duration",
              value: format_duration(result.duration_ms),
              inline: true
            },
            %{
              name: "Tasks",
              value: discord_task_summary(result.tasks),
              inline: false
            }
          ],
          timestamp: DateTime.to_iso8601(result.finished_at),
          footer: %{
            text: "Nexus Deployment"
          }
        }
      ]
    }
  end

  @doc """
  Generates a Microsoft Teams Adaptive Card formatted message payload.
  """
  @spec teams(pipeline_result()) :: map()
  def teams(result) do
    %{
      "@type" => "MessageCard",
      "@context" => "http://schema.org/extensions",
      "themeColor" => teams_color(result.status),
      "summary" => "Nexus Pipeline #{status_text(result.status)}",
      "sections" => [
        %{
          "activityTitle" => teams_title(result.status),
          "facts" => [
            %{"name" => "Status", "value" => status_text(result.status)},
            %{"name" => "Duration", "value" => format_duration(result.duration_ms)},
            %{"name" => "Started", "value" => format_time(result.started_at)},
            %{"name" => "Finished", "value" => format_time(result.finished_at)}
          ],
          "markdown" => true
        },
        %{
          "title" => "Task Results",
          "text" => teams_task_summary(result.tasks)
        }
      ]
    }
  end

  @doc """
  Generates a generic JSON payload suitable for most webhooks.
  """
  @spec generic(pipeline_result()) :: map()
  def generic(result) do
    %{
      event: "pipeline_completed",
      status: result.status,
      duration_ms: result.duration_ms,
      started_at: DateTime.to_iso8601(result.started_at),
      finished_at: DateTime.to_iso8601(result.finished_at),
      tasks:
        Enum.map(result.tasks, fn task ->
          %{
            name: task.name,
            status: task.status,
            hosts:
              Enum.map(task.hosts, fn host ->
                %{
                  host: host.host,
                  status: host.status,
                  error: host[:error]
                }
              end)
          }
        end),
      summary: %{
        total_tasks: length(result.tasks),
        successful: Enum.count(result.tasks, &(&1.status == :success)),
        failed: Enum.count(result.tasks, &(&1.status == :failure)),
        skipped: Enum.count(result.tasks, &(&1.status == :skipped))
      }
    }
  end

  # Private helpers

  defp slack_header(:success), do: "Pipeline Completed Successfully"
  defp slack_header(:failure), do: "Pipeline Failed"
  defp slack_header(:partial), do: "Pipeline Partially Completed"

  defp status_emoji(:success), do: ":white_check_mark:"
  defp status_emoji(:failure), do: ":x:"
  defp status_emoji(:partial), do: ":warning:"

  defp status_text(:success), do: "Success"
  defp status_text(:failure), do: "Failed"
  defp status_text(:partial), do: "Partial"

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"

  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = rem(ms, 60_000) |> div(1000)
    "#{minutes}m #{seconds}s"
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp slack_task_summary(tasks) do
    Enum.map_join(tasks, "\n", fn task ->
      emoji =
        case task.status do
          :success -> ":white_check_mark:"
          :failure -> ":x:"
          :skipped -> ":fast_forward:"
        end

      "#{emoji} `#{task.name}` - #{status_text(task.status)}"
    end)
  end

  defp discord_title(:success), do: "Pipeline Completed Successfully"
  defp discord_title(:failure), do: "Pipeline Failed"
  defp discord_title(:partial), do: "Pipeline Partially Completed"

  defp discord_color(:success), do: 0x2ECC71
  defp discord_color(:failure), do: 0xE74C3C
  defp discord_color(:partial), do: 0xF39C12

  defp discord_task_summary(tasks) do
    Enum.map_join(tasks, "\n", fn task ->
      emoji =
        case task.status do
          :success -> "+"
          :failure -> "-"
          :skipped -> "~"
        end

      "#{emoji} #{task.name}"
    end)
  end

  defp teams_title(:success), do: "Pipeline Completed Successfully"
  defp teams_title(:failure), do: "Pipeline Failed"
  defp teams_title(:partial), do: "Pipeline Partially Completed"

  defp teams_color(:success), do: "2ECC71"
  defp teams_color(:failure), do: "E74C3C"
  defp teams_color(:partial), do: "F39C12"

  defp teams_task_summary(tasks) do
    Enum.map_join(tasks, "\n\n", fn task ->
      icon =
        case task.status do
          :success -> "+"
          :failure -> "-"
          :skipped -> "~"
        end

      "#{icon} **#{task.name}**: #{status_text(task.status)}"
    end)
  end
end

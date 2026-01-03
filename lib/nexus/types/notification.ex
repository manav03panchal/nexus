defmodule Nexus.Types.Notification do
  @moduledoc """
  Represents a notification configuration for pipeline events.

  Notifications are sent to webhook URLs after pipeline completion,
  with support for various formats like Slack, Discord, and Teams.
  """

  @type template :: :slack | :discord | :teams | :generic
  @type trigger :: :success | :failure | :always

  @type t :: %__MODULE__{
          url: String.t(),
          template: template(),
          on: [trigger()],
          headers: %{String.t() => String.t()}
        }

  @enforce_keys [:url]
  defstruct [
    :url,
    template: :generic,
    on: [:always],
    headers: %{}
  ]

  @doc """
  Creates a new Notification configuration.

  The template is auto-detected from the URL if not specified:
  - Discord webhooks (`discord.com/api/webhooks/`) use `:discord` template
  - Slack webhooks (`hooks.slack.com/`) use `:slack` template
  - Teams webhooks (`webhook.office.com/`) use `:teams` template
  - Other URLs default to `:generic` template

  ## Options

    * `:template` - Message format (`:slack`, `:discord`, `:teams`, `:generic`). Auto-detected if not specified.
    * `:on` - When to send (`:success`, `:failure`, `:always`)
    * `:headers` - Additional HTTP headers

  ## Examples

      # Auto-detected as Discord template
      Notification.new("https://discord.com/api/webhooks/...")

      # Auto-detected as Slack template
      Notification.new("https://hooks.slack.com/...")

      # Explicit template override
      Notification.new("https://custom.webhook.com/...", template: :generic)

      # Only notify on failure
      Notification.new("https://discord.com/api/webhooks/...", on: [:failure])

  """
  @spec new(String.t(), keyword()) :: t()
  def new(url, opts \\ []) when is_binary(url) do
    on = Keyword.get(opts, :on, [:always]) |> normalize_on()
    template = Keyword.get(opts, :template) || detect_template(url)

    %__MODULE__{
      url: url,
      template: template,
      on: on,
      headers: Keyword.get(opts, :headers, %{})
    }
  end

  defp normalize_on(triggers) when is_list(triggers), do: triggers
  defp normalize_on(trigger) when is_atom(trigger), do: [trigger]

  @doc """
  Auto-detects the notification template from the webhook URL.
  """
  @spec detect_template(String.t()) :: template()
  def detect_template(url) when is_binary(url) do
    cond do
      String.contains?(url, "discord.com/api/webhooks") -> :discord
      String.contains?(url, "discordapp.com/api/webhooks") -> :discord
      String.contains?(url, "hooks.slack.com") -> :slack
      String.contains?(url, "webhook.office.com") -> :teams
      String.contains?(url, "outlook.office.com/webhook") -> :teams
      true -> :generic
    end
  end

  @doc """
  Checks if notification should be sent for the given status.
  """
  @spec should_send?(t(), :success | :failure) :: boolean()
  def should_send?(%__MODULE__{on: triggers}, status) do
    :always in triggers or status in triggers
  end
end

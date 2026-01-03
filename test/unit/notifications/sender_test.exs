defmodule Nexus.Notifications.SenderTest do
  use ExUnit.Case, async: true

  alias Nexus.Notifications.Sender
  alias Nexus.Types.Notification

  import Mox

  setup :verify_on_exit!

  @success_result %{
    status: :success,
    duration_ms: 5000,
    started_at: ~U[2024-01-01 10:00:00Z],
    finished_at: ~U[2024-01-01 10:00:05Z],
    tasks: [
      %{
        name: :build,
        status: :success,
        hosts: [%{host: "web1", status: :success, output: nil, error: nil}]
      }
    ]
  }

  describe "build_payload/2" do
    test "builds slack payload" do
      payload = Sender.build_payload(:slack, @success_result)

      assert Map.has_key?(payload, :blocks)
      assert is_list(payload.blocks)
    end

    test "builds discord payload" do
      payload = Sender.build_payload(:discord, @success_result)

      assert Map.has_key?(payload, :embeds)
      assert is_list(payload.embeds)
    end

    test "builds teams payload" do
      payload = Sender.build_payload(:teams, @success_result)

      assert Map.has_key?(payload, "@type")
      assert payload["@type"] == "MessageCard"
    end

    test "builds generic payload" do
      payload = Sender.build_payload(:generic, @success_result)

      assert payload.event == "pipeline_completed"
      assert payload.status == :success
      assert payload.duration_ms == 5000
    end

    test "falls back to generic for unknown template" do
      payload = Sender.build_payload(:unknown, @success_result)

      assert payload.event == "pipeline_completed"
    end
  end

  describe "Notification.should_send?/2" do
    test "sends on :always trigger for success" do
      notification = Notification.new("http://example.com", on: [:always])
      assert Notification.should_send?(notification, :success)
    end

    test "sends on :always trigger for failure" do
      notification = Notification.new("http://example.com", on: [:always])
      assert Notification.should_send?(notification, :failure)
    end

    test "sends on :success trigger for success status" do
      notification = Notification.new("http://example.com", on: [:success])
      assert Notification.should_send?(notification, :success)
    end

    test "does not send on :success trigger for failure status" do
      notification = Notification.new("http://example.com", on: [:success])
      refute Notification.should_send?(notification, :failure)
    end

    test "sends on :failure trigger for failure status" do
      notification = Notification.new("http://example.com", on: [:failure])
      assert Notification.should_send?(notification, :failure)
    end

    test "does not send on :failure trigger for success status" do
      notification = Notification.new("http://example.com", on: [:failure])
      refute Notification.should_send?(notification, :success)
    end

    test "handles multiple triggers" do
      notification = Notification.new("http://example.com", on: [:success, :failure])
      assert Notification.should_send?(notification, :success)
      assert Notification.should_send?(notification, :failure)
    end
  end

  describe "Notification.new/2" do
    test "creates notification with defaults" do
      notification = Notification.new("http://example.com")

      assert notification.url == "http://example.com"
      assert notification.template == :generic
      assert notification.on == [:always]
      assert notification.headers == %{}
    end

    test "creates notification with custom options" do
      notification =
        Notification.new("http://slack.com/webhook",
          template: :slack,
          on: :failure,
          headers: %{"Authorization" => "Bearer token"}
        )

      assert notification.template == :slack
      assert notification.on == [:failure]
      assert notification.headers == %{"Authorization" => "Bearer token"}
    end
  end
end

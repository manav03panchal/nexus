defmodule Nexus.Types.NotificationTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.Notification

  describe "new/2" do
    test "creates notification with URL" do
      notification = Notification.new("https://hooks.slack.com/services/xxx")

      assert notification.url == "https://hooks.slack.com/services/xxx"
    end

    test "uses default template :generic" do
      notification = Notification.new("http://example.com")

      assert notification.template == :generic
    end

    test "uses default on [:always]" do
      notification = Notification.new("http://example.com")

      assert notification.on == [:always]
    end

    test "uses default empty headers" do
      notification = Notification.new("http://example.com")

      assert notification.headers == %{}
    end

    test "accepts custom template" do
      notification = Notification.new("http://example.com", template: :slack)

      assert notification.template == :slack
    end

    test "accepts custom on triggers as list" do
      notification = Notification.new("http://example.com", on: [:success, :failure])

      assert notification.on == [:success, :failure]
    end

    test "normalizes single atom on trigger to list" do
      notification = Notification.new("http://example.com", on: :failure)

      assert notification.on == [:failure]
    end

    test "accepts custom headers" do
      headers = %{"Authorization" => "Bearer token", "X-Custom" => "value"}
      notification = Notification.new("http://example.com", headers: headers)

      assert notification.headers == headers
    end

    test "accepts all options together" do
      notification =
        Notification.new("http://discord.com/webhook",
          template: :discord,
          on: [:failure],
          headers: %{"X-Api-Key" => "secret"}
        )

      assert notification.url == "http://discord.com/webhook"
      assert notification.template == :discord
      assert notification.on == [:failure]
      assert notification.headers == %{"X-Api-Key" => "secret"}
    end
  end

  describe "should_send?/2" do
    test "returns true for :always trigger regardless of status" do
      notification = Notification.new("http://example.com", on: [:always])

      assert Notification.should_send?(notification, :success)
      assert Notification.should_send?(notification, :failure)
    end

    test "returns true for :success trigger when status is success" do
      notification = Notification.new("http://example.com", on: [:success])

      assert Notification.should_send?(notification, :success)
    end

    test "returns false for :success trigger when status is failure" do
      notification = Notification.new("http://example.com", on: [:success])

      refute Notification.should_send?(notification, :failure)
    end

    test "returns true for :failure trigger when status is failure" do
      notification = Notification.new("http://example.com", on: [:failure])

      assert Notification.should_send?(notification, :failure)
    end

    test "returns false for :failure trigger when status is success" do
      notification = Notification.new("http://example.com", on: [:failure])

      refute Notification.should_send?(notification, :success)
    end

    test "handles multiple triggers correctly" do
      notification = Notification.new("http://example.com", on: [:success, :failure])

      assert Notification.should_send?(notification, :success)
      assert Notification.should_send?(notification, :failure)
    end
  end

  describe "struct" do
    test "enforces url key" do
      assert_raise ArgumentError, fn ->
        struct!(Notification, template: :slack)
      end
    end
  end
end

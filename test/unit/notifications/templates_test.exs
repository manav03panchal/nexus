defmodule Nexus.Notifications.TemplatesTest do
  use ExUnit.Case, async: true

  alias Nexus.Notifications.Templates

  @success_result %{
    status: :success,
    duration_ms: 5432,
    started_at: ~U[2024-01-01 10:00:00Z],
    finished_at: ~U[2024-01-01 10:00:05Z],
    tasks: [
      %{
        name: :build,
        status: :success,
        hosts: [%{host: "web1", status: :success, output: nil, error: nil}]
      },
      %{
        name: :deploy,
        status: :success,
        hosts: [
          %{host: "web1", status: :success, output: nil, error: nil},
          %{host: "web2", status: :success, output: nil, error: nil}
        ]
      }
    ]
  }

  @failure_result %{
    status: :failure,
    duration_ms: 3000,
    started_at: ~U[2024-01-01 10:00:00Z],
    finished_at: ~U[2024-01-01 10:00:03Z],
    tasks: [
      %{
        name: :build,
        status: :success,
        hosts: [%{host: "builder", status: :success, output: nil, error: nil}]
      },
      %{
        name: :deploy,
        status: :failure,
        hosts: [%{host: "web1", status: :failure, output: nil, error: "Connection timeout"}]
      }
    ]
  }

  describe "slack/1" do
    test "returns Slack Block Kit format" do
      payload = Templates.slack(@success_result)

      assert Map.has_key?(payload, :blocks)
      assert is_list(payload.blocks)
      refute Enum.empty?(payload.blocks)
    end

    test "includes header block" do
      payload = Templates.slack(@success_result)

      header = Enum.find(payload.blocks, &(&1.type == "header"))
      assert header != nil
      assert header.text.text =~ "Success"
    end

    test "includes status and duration fields" do
      payload = Templates.slack(@success_result)

      section =
        Enum.find(payload.blocks, fn block ->
          block.type == "section" && Map.has_key?(block, :fields)
        end)

      assert section != nil
      field_texts = Enum.map(section.fields, & &1.text)
      assert Enum.any?(field_texts, &(&1 =~ "Status"))
      assert Enum.any?(field_texts, &(&1 =~ "Duration"))
    end

    test "includes task summary" do
      payload = Templates.slack(@success_result)

      task_section =
        Enum.find(payload.blocks, fn block ->
          block.type == "section" && Map.has_key?(block, :text) && block.text.text =~ "build"
        end)

      assert task_section != nil
    end

    test "shows failure status correctly" do
      payload = Templates.slack(@failure_result)

      header = Enum.find(payload.blocks, &(&1.type == "header"))
      assert header.text.text =~ "Failed"
    end
  end

  describe "discord/1" do
    test "returns Discord embed format" do
      payload = Templates.discord(@success_result)

      assert Map.has_key?(payload, :embeds)
      assert length(payload.embeds) == 1
    end

    test "includes embed with title and color" do
      payload = Templates.discord(@success_result)
      embed = hd(payload.embeds)

      assert Map.has_key?(embed, :title)
      assert Map.has_key?(embed, :color)
      assert embed.title =~ "Success"
    end

    test "includes fields for status and duration" do
      payload = Templates.discord(@success_result)
      embed = hd(payload.embeds)

      assert Map.has_key?(embed, :fields)
      field_names = Enum.map(embed.fields, & &1.name)
      assert "Status" in field_names
      assert "Duration" in field_names
      assert "Tasks" in field_names
    end

    test "includes timestamp and footer" do
      payload = Templates.discord(@success_result)
      embed = hd(payload.embeds)

      assert Map.has_key?(embed, :timestamp)
      assert Map.has_key?(embed, :footer)
    end

    test "uses different color for failure" do
      success_payload = Templates.discord(@success_result)
      failure_payload = Templates.discord(@failure_result)

      success_color = hd(success_payload.embeds).color
      failure_color = hd(failure_payload.embeds).color

      assert success_color != failure_color
    end
  end

  describe "teams/1" do
    test "returns Microsoft Teams MessageCard format" do
      payload = Templates.teams(@success_result)

      assert payload["@type"] == "MessageCard"
      assert payload["@context"] == "http://schema.org/extensions"
    end

    test "includes theme color" do
      payload = Templates.teams(@success_result)

      assert Map.has_key?(payload, "themeColor")
      assert is_binary(payload["themeColor"])
    end

    test "includes sections with facts" do
      payload = Templates.teams(@success_result)

      assert Map.has_key?(payload, "sections")
      assert payload["sections"] != []

      first_section = hd(payload["sections"])
      assert Map.has_key?(first_section, "facts")
    end

    test "includes summary" do
      payload = Templates.teams(@success_result)

      assert Map.has_key?(payload, "summary")
      assert payload["summary"] =~ "Pipeline"
    end
  end

  describe "generic/1" do
    test "returns structured JSON payload" do
      payload = Templates.generic(@success_result)

      assert payload.event == "pipeline_completed"
      assert payload.status == :success
      assert payload.duration_ms == 5432
    end

    test "includes ISO8601 timestamps" do
      payload = Templates.generic(@success_result)

      assert payload.started_at == "2024-01-01T10:00:00Z"
      assert payload.finished_at == "2024-01-01T10:00:05Z"
    end

    test "includes task details" do
      payload = Templates.generic(@success_result)

      assert is_list(payload.tasks)
      assert length(payload.tasks) == 2

      build_task = Enum.find(payload.tasks, &(&1.name == :build))
      assert build_task.status == :success
    end

    test "includes summary statistics" do
      payload = Templates.generic(@success_result)

      assert Map.has_key?(payload, :summary)
      assert payload.summary.total_tasks == 2
      assert payload.summary.successful == 2
      assert payload.summary.failed == 0
    end

    test "counts failures correctly" do
      payload = Templates.generic(@failure_result)

      assert payload.summary.successful == 1
      assert payload.summary.failed == 1
    end
  end
end

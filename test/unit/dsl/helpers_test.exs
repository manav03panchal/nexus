defmodule Nexus.DSL.HelpersTest do
  use ExUnit.Case, async: true

  alias Nexus.DSL.Parser.DSL, as: Parser

  describe "timestamp/0" do
    test "returns ISO 8601 formatted timestamp" do
      ts = Parser.do_timestamp()
      assert String.match?(ts, ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end
  end

  describe "git_sha/0" do
    test "returns a git SHA or 'unknown'" do
      sha = Parser.do_git_sha()
      # Either a valid short SHA (7+ hex chars) or "unknown"
      assert sha == "unknown" or String.match?(sha, ~r/^[a-f0-9]{7,}$/)
    end
  end

  describe "git_branch/0" do
    test "returns a branch name or 'unknown'" do
      branch = Parser.do_git_branch()
      assert is_binary(branch)
      assert byte_size(branch) > 0
    end
  end

  describe "git_tag/0" do
    test "returns nil or a tag name" do
      tag = Parser.do_git_tag()
      assert is_nil(tag) or is_binary(tag)
    end
  end

  describe "hostname/0" do
    test "returns actual hostname string" do
      result = Parser.do_hostname()
      assert is_binary(result)
      assert byte_size(result) > 0
    end

    test "returns hostname from process dictionary if set" do
      Process.put(:nexus_current_host, %{hostname: "test-server.example.com"})
      assert Parser.do_hostname() == "test-server.example.com"
      Process.delete(:nexus_current_host)
    end

    test "returns binary host from process dictionary" do
      Process.put(:nexus_current_host, "my-host")
      assert Parser.do_hostname() == "my-host"
      Process.delete(:nexus_current_host)
    end
  end

  describe "shard_id/0" do
    test "returns 0 by default" do
      assert Parser.do_shard_id() == 0
    end

    test "returns shard_id from process dictionary" do
      Process.put(:nexus_shard_id, 5)
      assert Parser.do_shard_id() == 5
      Process.delete(:nexus_shard_id)
    end
  end

  describe "shard_count/0" do
    test "returns 1 by default" do
      assert Parser.do_shard_count() == 1
    end

    test "returns shard_count from process dictionary" do
      Process.put(:nexus_shard_count, 10)
      assert Parser.do_shard_count() == 10
      Process.delete(:nexus_shard_count)
    end
  end

  describe "shard_items/1" do
    test "returns all items when shard_count is 1" do
      items = [:a, :b, :c, :d, :e]
      assert Parser.do_shard_items(items) == items
    end

    test "divides items across shards" do
      items = [:a, :b, :c, :d, :e, :f]

      # Shard 0 of 3
      Process.put(:nexus_shard_id, 0)
      Process.put(:nexus_shard_count, 3)
      assert Parser.do_shard_items(items) == [:a, :d]

      # Shard 1 of 3
      Process.put(:nexus_shard_id, 1)
      assert Parser.do_shard_items(items) == [:b, :e]

      # Shard 2 of 3
      Process.put(:nexus_shard_id, 2)
      assert Parser.do_shard_items(items) == [:c, :f]

      Process.delete(:nexus_shard_id)
      Process.delete(:nexus_shard_count)
    end

    test "handles uneven division" do
      items = [:a, :b, :c, :d, :e]

      # 5 items across 2 shards
      Process.put(:nexus_shard_id, 0)
      Process.put(:nexus_shard_count, 2)
      assert Parser.do_shard_items(items) == [:a, :c, :e]

      Process.put(:nexus_shard_id, 1)
      assert Parser.do_shard_items(items) == [:b, :d]

      Process.delete(:nexus_shard_id)
      Process.delete(:nexus_shard_count)
    end

    test "handles empty list" do
      assert Parser.do_shard_items([]) == []
    end
  end
end

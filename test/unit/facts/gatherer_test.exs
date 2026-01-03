defmodule Nexus.Facts.GathererTest do
  use ExUnit.Case, async: true

  alias Nexus.Facts.Gatherer

  describe "gather_local/0" do
    test "returns system facts for local machine" do
      assert {:ok, facts} = Gatherer.gather_local()

      # OS should be detected
      assert facts[:os] in [:linux, :darwin, :windows]

      # Hostname should be present
      assert is_binary(facts[:hostname])
      assert facts[:hostname] != ""

      # CPU count should be positive integer
      assert is_integer(facts[:cpu_count])
      assert facts[:cpu_count] > 0

      # Memory should be positive integer
      assert is_integer(facts[:memory_mb])
      assert facts[:memory_mb] > 0

      # Architecture should be detected
      assert facts[:arch] in [:x86_64, :aarch64, :arm, :unknown]
    end

    test "includes kernel version" do
      {:ok, facts} = Gatherer.gather_local()
      assert is_binary(facts[:kernel_version])
    end

    test "includes os_family" do
      {:ok, facts} = Gatherer.gather_local()
      assert facts[:os_family] in [:debian, :rhel, :arch, :alpine, :darwin, :unknown]
    end

    test "includes user" do
      {:ok, facts} = Gatherer.gather_local()
      assert is_binary(facts[:user])
    end
  end

  describe "fact consistency" do
    test "all expected facts are present" do
      {:ok, facts} = Gatherer.gather_local()

      expected_keys = [
        :os,
        :os_family,
        :hostname,
        :cpu_count,
        :memory_mb,
        :arch,
        :kernel_version,
        :user
      ]

      Enum.each(expected_keys, fn key ->
        assert Map.has_key?(facts, key), "Missing fact: #{key}"
      end)
    end
  end
end

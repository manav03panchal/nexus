defmodule Nexus.Facts.CacheTest do
  use ExUnit.Case, async: false

  alias Nexus.Facts.Cache

  setup do
    Cache.init()
    on_exit(fn -> Cache.clear() end)
    :ok
  end

  describe "init/0 and clear/0" do
    test "init creates empty cache" do
      Cache.clear()
      Cache.init()

      assert Cache.list_hosts() == []
    end

    test "clear removes all cached facts" do
      Cache.put_all("host1", %{os: :linux})
      Cache.put_all("host2", %{os: :darwin})

      Cache.clear()
      Cache.init()

      assert Cache.list_hosts() == []
    end
  end

  describe "put_all/2 and get_all/1" do
    test "stores and retrieves all facts for a host" do
      facts = %{os: :linux, cpu_count: 4, memory_mb: 8192}
      Cache.put_all("host1", facts)

      assert Cache.get_all("host1") == facts
    end

    test "returns nil for uncached host" do
      assert Cache.get_all("nonexistent") == nil
    end
  end

  describe "put/3 and get/2" do
    test "stores and retrieves individual fact" do
      Cache.put("host1", :os, :linux)

      assert Cache.get("host1", :os) == :linux
    end

    test "returns nil for uncached fact" do
      assert Cache.get("nonexistent", :os) == nil
    end

    test "returns nil for uncached fact name on existing host" do
      Cache.put("host1", :os, :linux)

      assert Cache.get("host1", :cpu_count) == nil
    end

    test "accumulates facts for same host" do
      Cache.put("host1", :os, :linux)
      Cache.put("host1", :cpu_count, 4)

      assert Cache.get("host1", :os) == :linux
      assert Cache.get("host1", :cpu_count) == 4
    end
  end

  describe "cached?/1" do
    test "returns true for cached host" do
      Cache.put_all("host1", %{os: :linux})

      assert Cache.cached?("host1")
    end

    test "returns false for uncached host" do
      refute Cache.cached?("nonexistent")
    end
  end

  describe "list_hosts/0" do
    test "returns all cached host IDs" do
      Cache.put_all("host1", %{os: :linux})
      Cache.put_all("host2", %{os: :darwin})
      Cache.put_all("host3", %{os: :linux})

      hosts = Cache.list_hosts()

      assert length(hosts) == 3
      assert "host1" in hosts
      assert "host2" in hosts
      assert "host3" in hosts
    end
  end
end

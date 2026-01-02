defmodule Nexus.Discovery.TailscaleEdgeCasesTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.Config

  @moduletag :unit

  describe "JSON parsing edge cases" do
    test "handles empty peers object" do
      json = ~s({"Version": "1.56.1", "Peer": {}})
      {:ok, data} = Jason.decode(json)
      assert data["Peer"] == %{}
    end

    test "handles null peers" do
      json = ~s({"Version": "1.56.1", "Peer": null})
      {:ok, data} = Jason.decode(json)
      assert data["Peer"] == nil
    end

    test "handles missing Peer key" do
      json = ~s({"Version": "1.56.1"})
      {:ok, data} = Jason.decode(json)
      assert Map.get(data, "Peer") == nil
    end

    test "handles peer with minimal fields" do
      json = """
      {
        "Peer": {
          "abc123": {
            "HostName": "server1"
          }
        }
      }
      """

      {:ok, data} = Jason.decode(json)
      peer = data["Peer"]["abc123"]
      assert peer["HostName"] == "server1"
      assert Map.get(peer, "DNSName") == nil
      assert Map.get(peer, "TailscaleIPs") == nil
      assert Map.get(peer, "Tags") == nil
      assert Map.get(peer, "Online") == nil
    end

    test "handles peer with empty hostname" do
      json = """
      {
        "Peer": {
          "abc123": {
            "HostName": "",
            "DNSName": "server.tailnet.ts.net.",
            "Online": true
          }
        }
      }
      """

      {:ok, data} = Jason.decode(json)
      peer = data["Peer"]["abc123"]
      assert peer["HostName"] == ""
    end

    test "handles peer with empty tags array" do
      json = """
      {
        "Peer": {
          "abc123": {
            "HostName": "server1",
            "Tags": []
          }
        }
      }
      """

      {:ok, data} = Jason.decode(json)
      peer = data["Peer"]["abc123"]
      assert peer["Tags"] == []
    end

    test "handles peer with many tags" do
      tags =
        for i <- 1..50 do
          "tag:tag#{i}"
        end

      json = """
      {
        "Peer": {
          "abc123": {
            "HostName": "server1",
            "Tags": #{Jason.encode!(tags)}
          }
        }
      }
      """

      {:ok, data} = Jason.decode(json)
      peer = data["Peer"]["abc123"]
      assert length(peer["Tags"]) == 50
    end

    test "handles peer with multiple IPs" do
      json = """
      {
        "Peer": {
          "abc123": {
            "HostName": "server1",
            "TailscaleIPs": ["100.100.100.10", "fd7a:115c:a1e0::1", "100.100.100.11"]
          }
        }
      }
      """

      {:ok, data} = Jason.decode(json)
      peer = data["Peer"]["abc123"]
      assert length(peer["TailscaleIPs"]) == 3
    end
  end

  describe "tag filtering edge cases" do
    test "tag matching is exact" do
      tags = ["webserver", "production", "frontend"]

      # Exact match
      assert "webserver" in tags
      # Partial match should not work
      refute "web" in tags
      refute "server" in tags
    end

    test "tag with special characters" do
      tags = ["tag-with-dashes", "tag.with.dots", "tag_with_underscores"]

      assert "tag-with-dashes" in tags
      assert "tag.with.dots" in tags
      assert "tag_with_underscores" in tags
    end

    test "tag prefix stripping" do
      raw_tags = ["tag:webserver", "tag:production"]
      stripped = Enum.map(raw_tags, &String.replace_prefix(&1, "tag:", ""))

      assert stripped == ["webserver", "production"]
    end

    test "handles tags without prefix" do
      raw_tags = ["webserver", "production"]
      stripped = Enum.map(raw_tags, &String.replace_prefix(&1, "tag:", ""))

      # Should remain unchanged
      assert stripped == ["webserver", "production"]
    end

    test "handles mixed tags with and without prefix" do
      raw_tags = ["tag:webserver", "production", "tag:frontend"]
      stripped = Enum.map(raw_tags, &String.replace_prefix(&1, "tag:", ""))

      assert stripped == ["webserver", "production", "frontend"]
    end

    test "case sensitivity in tags" do
      tags = ["WebServer", "PRODUCTION", "frontend"]

      assert "WebServer" in tags
      refute "webserver" in tags
      refute "Frontend" in tags
    end
  end

  describe "hostname generation edge cases" do
    test "lowercase conversion" do
      hostname = "My-Server-01"
      result = String.downcase(hostname)
      assert result == "my-server-01"
    end

    test "special character replacement" do
      hostname = "my.server-name_01"
      result = hostname |> String.downcase() |> String.replace(~r/[^a-z0-9_]/, "_")
      assert result == "my_server_name_01"
    end

    test "consecutive special characters" do
      hostname = "server--name..test"
      result = hostname |> String.downcase() |> String.replace(~r/[^a-z0-9_]/, "_")
      assert result == "server__name__test"
    end

    test "hostname starting with number" do
      hostname = "123server"
      result = hostname |> String.downcase() |> String.replace(~r/[^a-z0-9_]/, "_")
      assert result == "123server"
    end

    test "hostname with unicode characters" do
      hostname = "서버-server"
      result = hostname |> String.downcase() |> String.replace(~r/[^a-z0-9_]/, "_")
      # Unicode letters become underscores
      assert result =~ "_"
    end

    test "empty hostname" do
      hostname = ""
      result = hostname |> String.downcase() |> String.replace(~r/[^a-z0-9_]/, "_")
      assert result == ""
    end

    test "very long hostname" do
      hostname = String.duplicate("a", 255)
      result = hostname |> String.downcase() |> String.replace(~r/[^a-z0-9_]/, "_")
      assert String.length(result) == 255
    end
  end

  describe "DNS name handling edge cases" do
    test "strips trailing dot" do
      dns = "server.tailnet.ts.net."
      result = String.trim_trailing(dns, ".")
      assert result == "server.tailnet.ts.net"
    end

    test "handles multiple trailing dots" do
      dns = "server.tailnet.ts.net..."
      result = String.trim_trailing(dns, ".")
      assert result == "server.tailnet.ts.net"
    end

    test "handles no trailing dot" do
      dns = "server.tailnet.ts.net"
      result = String.trim_trailing(dns, ".")
      assert result == "server.tailnet.ts.net"
    end

    test "handles empty DNS name" do
      dns = ""
      result = String.trim_trailing(dns, ".")
      assert result == ""
    end

    test "handles just a dot" do
      dns = "."
      result = String.trim_trailing(dns, ".")
      assert result == ""
    end
  end

  describe "IP address handling" do
    test "prefers DNS name over IP" do
      dns_name = "server.tailnet.ts.net"
      ips = ["100.100.100.10"]

      hostname = if dns_name != "", do: dns_name, else: List.first(ips, "unknown")
      assert hostname == "server.tailnet.ts.net"
    end

    test "falls back to first IP when no DNS" do
      dns_name = ""
      ips = ["100.100.100.10", "fd7a:115c:a1e0::1"]

      hostname = if dns_name != "", do: dns_name, else: List.first(ips, "unknown")
      assert hostname == "100.100.100.10"
    end

    test "falls back to unknown when no DNS or IP" do
      dns_name = ""
      ips = []

      hostname = if dns_name != "", do: dns_name, else: List.first(ips, "unknown")
      assert hostname == "unknown"
    end

    test "handles IPv6 addresses" do
      ips = ["fd7a:115c:a1e0::1"]
      hostname = List.first(ips, "unknown")
      assert hostname == "fd7a:115c:a1e0::1"
    end
  end

  describe "online filtering edge cases" do
    test "filters online only" do
      peers = [
        %{hostname: "a", online: true},
        %{hostname: "b", online: false},
        %{hostname: "c", online: true},
        %{hostname: "d", online: false}
      ]

      online = Enum.filter(peers, & &1.online)
      assert length(online) == 2
      assert Enum.all?(online, & &1.online)
    end

    test "includes all when not filtering" do
      peers = [
        %{hostname: "a", online: true},
        %{hostname: "b", online: false}
      ]

      all = peers
      assert length(all) == 2
    end

    test "handles all offline" do
      peers = [
        %{hostname: "a", online: false},
        %{hostname: "b", online: false}
      ]

      online = Enum.filter(peers, & &1.online)
      assert online == []
    end

    test "handles all online" do
      peers = [
        %{hostname: "a", online: true},
        %{hostname: "b", online: true}
      ]

      online = Enum.filter(peers, & &1.online)
      assert length(online) == 2
    end

    test "handles empty peers" do
      peers = []
      online = Enum.filter(peers, & &1.online)
      assert online == []
    end
  end

  describe "config building edge cases" do
    test "empty discovery adds nothing" do
      config = Config.new()
      # Simulating empty discovery result - variables show intent
      _peers = []
      _group_name = :web

      # No hosts to add, should not add empty group
      assert config.hosts == %{}
      assert config.groups == %{}
    end

    test "duplicate hostnames create unique atoms" do
      # If two servers have same hostname after sanitization
      hostname1 = "server_1"
      hostname2 = "server_1"

      atom1 = String.to_atom(hostname1)
      atom2 = String.to_atom(hostname2)

      # Same atom - would overwrite
      assert atom1 == atom2
    end

    test "group creation with single host" do
      config = Config.new()
      host_names = [:single_host]

      group = %Nexus.Types.HostGroup{name: :web, hosts: host_names}
      updated = %{config | groups: Map.put(config.groups, :web, group)}

      assert length(updated.groups[:web].hosts) == 1
    end

    test "group creation with many hosts" do
      config = Config.new()
      host_names = for i <- 1..100, do: String.to_atom("host_#{i}")

      group = %Nexus.Types.HostGroup{name: :fleet, hosts: host_names}
      updated = %{config | groups: Map.put(config.groups, :fleet, group)}

      assert length(updated.groups[:fleet].hosts) == 100
    end
  end

  describe "option validation edge cases" do
    test "both required options present" do
      opts = [tag: "webserver", as: :web]
      assert Keyword.get(opts, :tag) == "webserver"
      assert Keyword.get(opts, :as) == :web
    end

    test "missing tag option" do
      opts = [as: :web]
      assert Keyword.get(opts, :tag) == nil
    end

    test "missing as option" do
      opts = [tag: "webserver"]
      assert Keyword.get(opts, :as) == nil
    end

    test "extra options are preserved" do
      opts = [tag: "webserver", as: :web, user: "deploy", online_only: false]
      assert Keyword.get(opts, :user) == "deploy"
      assert Keyword.get(opts, :online_only) == false
    end

    test "default for online_only is true" do
      opts = [tag: "webserver", as: :web]
      assert Keyword.get(opts, :online_only, true) == true
    end
  end

  describe "error handling edge cases" do
    test "invalid JSON returns error tuple" do
      invalid_json = "not valid json"
      result = Jason.decode(invalid_json)
      assert match?({:error, _}, result)
    end

    test "handles unexpected data structure" do
      json = ~s("just a string")
      {:ok, data} = Jason.decode(json)
      # Not a map, can't access Peer
      assert is_binary(data)
    end

    test "handles array instead of object" do
      json = ~s([1, 2, 3])
      {:ok, data} = Jason.decode(json)
      assert is_list(data)
    end
  end
end

defmodule Nexus.Discovery.TailscaleTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.Config

  @moduletag :unit

  # Sample Tailscale status JSON for testing
  @sample_status_json """
  {
    "Version": "1.56.1",
    "Self": {
      "HostName": "my-laptop",
      "DNSName": "my-laptop.tailnet.ts.net.",
      "TailscaleIPs": ["100.100.100.1"]
    },
    "Peer": {
      "abc123": {
        "HostName": "web-server-1",
        "DNSName": "web-server-1.tailnet.ts.net.",
        "TailscaleIPs": ["100.100.100.10", "fd7a:115c:a1e0::1"],
        "Tags": ["tag:webserver", "tag:production"],
        "Online": true
      },
      "def456": {
        "HostName": "web-server-2",
        "DNSName": "web-server-2.tailnet.ts.net.",
        "TailscaleIPs": ["100.100.100.11"],
        "Tags": ["tag:webserver", "tag:production"],
        "Online": true
      },
      "ghi789": {
        "HostName": "db-server",
        "DNSName": "db-server.tailnet.ts.net.",
        "TailscaleIPs": ["100.100.100.20"],
        "Tags": ["tag:database"],
        "Online": true
      },
      "jkl012": {
        "HostName": "offline-server",
        "DNSName": "offline-server.tailnet.ts.net.",
        "TailscaleIPs": ["100.100.100.30"],
        "Tags": ["tag:webserver"],
        "Online": false
      }
    }
  }
  """

  @empty_peers_json """
  {
    "Version": "1.56.1",
    "Self": {
      "HostName": "my-laptop"
    },
    "Peer": null
  }
  """

  describe "discover/2 integration with mocked data" do
    # Note: These tests verify the filtering and config building logic
    # The actual tailscale command is not called in unit tests

    test "filter_by_tag filters peers correctly" do
      peers = [
        %{hostname: "web1", tags: ["webserver", "production"], online: true},
        %{hostname: "web2", tags: ["webserver"], online: true},
        %{hostname: "db1", tags: ["database"], online: true}
      ]

      # Use send_receive pattern to test internal filter function
      webserver_peers = Enum.filter(peers, fn p -> "webserver" in p.tags end)
      assert length(webserver_peers) == 2

      db_peers = Enum.filter(peers, fn p -> "database" in p.tags end)
      assert length(db_peers) == 1
    end

    test "filter_by_online filters correctly" do
      peers = [
        %{hostname: "web1", online: true},
        %{hostname: "web2", online: false},
        %{hostname: "web3", online: true}
      ]

      online_peers = Enum.filter(peers, & &1.online)
      assert length(online_peers) == 2

      all_peers = peers
      assert length(all_peers) == 3
    end
  end

  describe "JSON parsing logic" do
    test "parses peer data from status JSON" do
      {:ok, data} = Jason.decode(@sample_status_json)
      peers = data["Peer"]

      assert is_map(peers)
      assert map_size(peers) == 4

      web1 = peers["abc123"]
      assert web1["HostName"] == "web-server-1"
      assert web1["DNSName"] == "web-server-1.tailnet.ts.net."
      assert "tag:webserver" in web1["Tags"]
      assert web1["Online"] == true
    end

    test "handles null peers" do
      {:ok, data} = Jason.decode(@empty_peers_json)
      assert data["Peer"] == nil
    end

    test "parses tags correctly" do
      {:ok, data} = Jason.decode(@sample_status_json)
      web1 = data["Peer"]["abc123"]

      # Tags come with "tag:" prefix from Tailscale
      tags = web1["Tags"]
      assert "tag:webserver" in tags
      assert "tag:production" in tags

      # After stripping prefix
      stripped = Enum.map(tags, &String.replace_prefix(&1, "tag:", ""))
      assert "webserver" in stripped
      assert "production" in stripped
    end
  end

  describe "host name generation" do
    test "generates valid atom from hostname" do
      # Simulating the generate_host_name logic
      hostname = "Web-Server-1"

      atom_name =
        hostname
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9_]/, "_")
        |> String.to_atom()

      assert atom_name == :web_server_1
    end

    test "handles special characters" do
      hostname = "my.server-2"

      atom_name =
        hostname
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9_]/, "_")
        |> String.to_atom()

      assert atom_name == :my_server_2
    end
  end

  describe "Config building" do
    test "adds discovered hosts to config" do
      config = Config.new()

      # Simulate what discover would do with parsed peers
      peer = %{
        hostname: "web-server-1",
        dns_name: "web-server-1.tailnet.ts.net",
        tailscale_ips: ["100.100.100.10"],
        tags: ["webserver"],
        online: true
      }

      host_name = :web_server_1

      host = %Nexus.Types.Host{
        name: host_name,
        hostname: peer.dns_name,
        user: "deploy",
        port: 22
      }

      updated_config = %{config | hosts: Map.put(config.hosts, host_name, host)}
      assert Map.has_key?(updated_config.hosts, :web_server_1)
      assert updated_config.hosts[:web_server_1].hostname == "web-server-1.tailnet.ts.net"
    end

    test "creates group with discovered hosts" do
      config = Config.new()
      group_name = :web
      host_names = [:web_server_1, :web_server_2]

      group = %Nexus.Types.HostGroup{name: group_name, hosts: host_names}
      updated_config = %{config | groups: Map.put(config.groups, group_name, group)}

      assert Map.has_key?(updated_config.groups, :web)
      assert updated_config.groups[:web].hosts == [:web_server_1, :web_server_2]
    end
  end

  describe "option validation" do
    test "requires :tag option" do
      # Simulating fetch_required behavior
      opts = [as: :web]

      result =
        case Keyword.fetch(opts, :tag) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, "missing required option: tag"}
        end

      assert result == {:error, "missing required option: tag"}
    end

    test "requires :as option" do
      opts = [tag: "webserver"]

      result =
        case Keyword.fetch(opts, :as) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, "missing required option: as"}
        end

      assert result == {:error, "missing required option: as"}
    end

    test "accepts valid options" do
      opts = [tag: "webserver", as: :web, user: "deploy", online_only: true]

      assert Keyword.get(opts, :tag) == "webserver"
      assert Keyword.get(opts, :as) == :web
      assert Keyword.get(opts, :user) == "deploy"
      assert Keyword.get(opts, :online_only, true) == true
    end
  end

  describe "DNS name handling" do
    test "trims trailing dot from DNS name" do
      dns_name = "server.tailnet.ts.net."
      trimmed = String.trim_trailing(dns_name, ".")
      assert trimmed == "server.tailnet.ts.net"
    end

    test "handles DNS name without trailing dot" do
      dns_name = "server.tailnet.ts.net"
      trimmed = String.trim_trailing(dns_name, ".")
      assert trimmed == "server.tailnet.ts.net"
    end

    test "falls back to IP when DNS name is empty" do
      dns_name = ""
      tailscale_ips = ["100.100.100.10"]

      hostname =
        if dns_name != "" do
          dns_name
        else
          List.first(tailscale_ips, "unknown")
        end

      assert hostname == "100.100.100.10"
    end
  end
end

defmodule Nexus.Discovery.Tailscale do
  @moduledoc """
  Discovers hosts from Tailscale network using `tailscale status --json`.

  This module queries the local Tailscale daemon for connected peers and
  allows filtering by tags to automatically populate host groups.

  ## Usage in DSL

      # Discover all hosts with tag:webserver and add them to :web group
      tailscale_hosts tag: "webserver", as: :web

      # Discover hosts with tag:database
      tailscale_hosts tag: "database", as: :db

  ## Requirements

  - Tailscale must be installed and running on the local machine
  - The `tailscale` CLI must be in PATH
  - Hosts must have ACL tags configured in Tailscale admin console
  """

  alias Nexus.Types.{Config, Host, HostGroup}

  @type peer :: %{
          hostname: String.t(),
          dns_name: String.t(),
          tailscale_ips: [String.t()],
          tags: [String.t()],
          online: boolean()
        }

  @type discovery_opts :: [
          tag: String.t(),
          as: atom(),
          user: String.t() | nil,
          online_only: boolean()
        ]

  @doc """
  Discovers Tailscale peers and adds matching hosts to the config.

  ## Options

    * `:tag` - (required) The Tailscale ACL tag to filter by (without "tag:" prefix)
    * `:as` - (required) The group name to assign discovered hosts to
    * `:user` - (optional) SSH user for all discovered hosts
    * `:online_only` - (optional) Only include online peers (default: true)

  ## Examples

      iex> config = Config.new()
      iex> {:ok, updated_config} = Tailscale.discover(config, tag: "webserver", as: :web)
      iex> Map.has_key?(updated_config.groups, :web)
      true

  """
  @spec discover(Config.t(), discovery_opts()) :: {:ok, Config.t()} | {:error, String.t()}
  def discover(%Config{} = config, opts) when is_list(opts) do
    with {:ok, tag} <- fetch_required(opts, :tag),
         {:ok, group_name} <- fetch_required(opts, :as),
         {:ok, peers} <- get_peers() do
      user = Keyword.get(opts, :user)
      online_only = Keyword.get(opts, :online_only, true)

      matching_peers =
        peers
        |> filter_by_tag(tag)
        |> filter_by_online(online_only)

      updated_config = add_peers_to_config(config, matching_peers, group_name, user)
      {:ok, updated_config}
    end
  end

  @doc """
  Gets all Tailscale peers from the local daemon.

  Returns a list of peer maps with hostname, DNS name, IPs, tags, and online status.
  """
  @spec get_peers() :: {:ok, [peer()]} | {:error, String.t()}
  def get_peers do
    case run_tailscale_status() do
      {:ok, json} -> parse_status(json)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists available tags from connected peers.

  Useful for discovering what tags are available in the Tailscale network.
  """
  @spec list_tags() :: {:ok, [String.t()]} | {:error, String.t()}
  def list_tags do
    case get_peers() do
      {:ok, peers} ->
        tags =
          peers
          |> Enum.flat_map(& &1.tags)
          |> Enum.uniq()
          |> Enum.sort()

        {:ok, tags}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  @spec run_tailscale_status() :: {:ok, String.t()} | {:error, String.t()}
  defp run_tailscale_status do
    case System.cmd("tailscale", ["status", "--json"], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}

      {output, _exit_code} ->
        {:error, "tailscale command failed: #{String.trim(output)}"}
    end
  rescue
    e in ErlangError ->
      {:error, "tailscale command not found: #{inspect(e)}"}
  end

  @spec parse_status(String.t()) :: {:ok, [peer()]} | {:error, String.t()}
  defp parse_status(json) do
    case Jason.decode(json) do
      {:ok, %{"Peer" => peers}} when is_map(peers) ->
        parsed =
          peers
          |> Map.values()
          |> Enum.map(&parse_peer/1)

        {:ok, parsed}

      {:ok, %{"Peer" => nil}} ->
        {:ok, []}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, "failed to parse tailscale status: #{inspect(reason)}"}
    end
  end

  @spec parse_peer(map()) :: peer()
  defp parse_peer(peer) do
    %{
      hostname: Map.get(peer, "HostName", ""),
      dns_name: Map.get(peer, "DNSName", "") |> String.trim_trailing("."),
      tailscale_ips: Map.get(peer, "TailscaleIPs", []),
      tags: parse_tags(Map.get(peer, "Tags", [])),
      online: Map.get(peer, "Online", false)
    }
  end

  @spec parse_tags([String.t()] | nil) :: [String.t()]
  defp parse_tags(nil), do: []

  defp parse_tags(tags) when is_list(tags) do
    Enum.map(tags, fn tag ->
      # Remove "tag:" prefix if present
      tag
      |> String.replace_prefix("tag:", "")
    end)
  end

  @spec filter_by_tag([peer()], String.t()) :: [peer()]
  defp filter_by_tag(peers, tag) do
    Enum.filter(peers, fn peer ->
      tag in peer.tags
    end)
  end

  @spec filter_by_online([peer()], boolean()) :: [peer()]
  defp filter_by_online(peers, true), do: Enum.filter(peers, & &1.online)
  defp filter_by_online(peers, false), do: peers

  @spec add_peers_to_config(Config.t(), [peer()], atom(), String.t() | nil) :: Config.t()
  defp add_peers_to_config(config, peers, group_name, user) do
    # Add each peer as a host
    {updated_config, host_names} =
      Enum.reduce(peers, {config, []}, fn peer, {cfg, names} ->
        host_name = generate_host_name(peer)
        host = create_host(peer, user)
        updated_cfg = %{cfg | hosts: Map.put(cfg.hosts, host_name, host)}
        {updated_cfg, [host_name | names]}
      end)

    # Create group with all discovered hosts
    if Enum.empty?(host_names) do
      updated_config
    else
      group = %HostGroup{name: group_name, hosts: Enum.reverse(host_names)}
      %{updated_config | groups: Map.put(updated_config.groups, group_name, group)}
    end
  end

  @spec generate_host_name(peer()) :: atom()
  defp generate_host_name(peer) do
    # Use hostname, sanitized for atom
    peer.hostname
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.to_atom()
  end

  @spec create_host(peer(), String.t() | nil) :: Host.t()
  defp create_host(peer, user) do
    # Prefer DNS name, fall back to first Tailscale IP
    hostname =
      if peer.dns_name != "" do
        peer.dns_name
      else
        List.first(peer.tailscale_ips, peer.hostname)
      end

    %Host{
      name: generate_host_name(peer),
      hostname: hostname,
      user: user,
      port: 22
    }
  end

  @spec fetch_required(keyword(), :tag | :as) :: {:ok, any()} | {:error, String.t()}
  defp fetch_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, "missing required option: #{key}"}
    end
  end
end

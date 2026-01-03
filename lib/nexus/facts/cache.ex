defmodule Nexus.Facts.Cache do
  @moduledoc """
  Caches gathered facts per host for the duration of a pipeline run.

  Facts are stored in the process dictionary to avoid passing state through
  the entire execution pipeline. The cache is cleared when the pipeline completes.

  ## Usage

  The cache is typically used via the `facts/1` DSL function:

      task :install, on: :web do
        run "apt install nginx", when: facts(:os_family) == :debian
        run "yum install nginx", when: facts(:os_family) == :rhel
      end

  """

  @cache_key :nexus_facts_cache

  @type host_id :: atom() | String.t()
  @type fact_name :: Nexus.Facts.Gatherer.fact_name()

  @doc """
  Initializes the facts cache for a pipeline run.
  """
  @spec init() :: :ok
  def init do
    Process.put(@cache_key, %{})
    :ok
  end

  @doc """
  Clears the facts cache.
  """
  @spec clear() :: :ok
  def clear do
    Process.delete(@cache_key)
    :ok
  end

  @doc """
  Gets a fact for a host, returning cached value or nil if not cached.
  """
  @spec get(host_id(), fact_name()) :: term() | nil
  def get(host_id, fact_name) do
    cache = Process.get(@cache_key, %{})

    case Map.get(cache, host_id) do
      nil -> nil
      host_facts -> Map.get(host_facts, fact_name)
    end
  end

  @doc """
  Gets all facts for a host, returning nil if not cached.
  """
  @spec get_all(host_id()) :: map() | nil
  def get_all(host_id) do
    cache = Process.get(@cache_key, %{})
    Map.get(cache, host_id)
  end

  @doc """
  Stores all facts for a host in the cache.
  """
  @spec put_all(host_id(), map()) :: :ok
  def put_all(host_id, facts) when is_map(facts) do
    cache = Process.get(@cache_key, %{})
    updated_cache = Map.put(cache, host_id, facts)
    Process.put(@cache_key, updated_cache)
    :ok
  end

  @doc """
  Stores a single fact for a host in the cache.
  """
  @spec put(host_id(), fact_name(), term()) :: :ok
  def put(host_id, fact_name, value) do
    cache = Process.get(@cache_key, %{})
    host_facts = Map.get(cache, host_id, %{})
    updated_host_facts = Map.put(host_facts, fact_name, value)
    updated_cache = Map.put(cache, host_id, updated_host_facts)
    Process.put(@cache_key, updated_cache)
    :ok
  end

  @doc """
  Checks if facts have been cached for a host.
  """
  @spec cached?(host_id()) :: boolean()
  def cached?(host_id) do
    cache = Process.get(@cache_key, %{})
    Map.has_key?(cache, host_id)
  end

  @doc """
  Lists all cached host IDs.
  """
  @spec list_hosts() :: [host_id()]
  def list_hosts do
    cache = Process.get(@cache_key, %{})
    Map.keys(cache)
  end
end

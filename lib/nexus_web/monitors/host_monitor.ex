defmodule NexusWeb.HostMonitor do
  @moduledoc """
  Background GenServer for monitoring host health.

  Performs periodic connectivity checks on configured hosts and
  broadcasts status updates via PubSub.
  """

  use GenServer

  alias Nexus.SSH.Connection
  alias Phoenix.PubSub

  @default_check_interval 60_000
  @tcp_timeout 5_000
  @ssh_timeout 10_000

  @type status ::
          :unknown
          | :checking
          | :reachable
          | :tcp_failed
          | :ssh_auth_failed
          | :ssh_timeout
          | :command_failed

  defstruct [
    :hosts,
    :host_statuses,
    :last_checks,
    :check_interval,
    :enabled,
    :config_file
  ]

  # Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check connectivity for a specific host.
  """
  def check_host(host_name) do
    GenServer.cast(__MODULE__, {:check_host, host_name})
  end

  @doc """
  Check all hosts.
  """
  def check_all do
    GenServer.cast(__MODULE__, :check_all)
  end

  @doc """
  Get the current status of a host.
  """
  def get_status(host_name) do
    GenServer.call(__MODULE__, {:get_status, host_name})
  end

  @doc """
  Get all host statuses.
  """
  def get_all_statuses do
    GenServer.call(__MODULE__, :get_all_statuses)
  end

  @doc """
  Update the hosts list from config.
  """
  def update_hosts(hosts) do
    GenServer.cast(__MODULE__, {:update_hosts, hosts})
  end

  @doc """
  Enable periodic monitoring.
  """
  def enable_monitoring do
    GenServer.cast(__MODULE__, :enable_monitoring)
  end

  @doc """
  Disable periodic monitoring.
  """
  def disable_monitoring do
    GenServer.cast(__MODULE__, :disable_monitoring)
  end

  # Callbacks

  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval)
    enabled = Keyword.get(opts, :enabled, false)

    state = %__MODULE__{
      hosts: %{},
      host_statuses: %{},
      last_checks: %{},
      check_interval: check_interval,
      enabled: enabled,
      config_file: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get_status, host_name}, _from, state) do
    status = Map.get(state.host_statuses, host_name, :unknown)
    {:reply, status, state}
  end

  def handle_call(:get_all_statuses, _from, state) do
    result =
      Enum.map(state.hosts, fn {name, host} ->
        %{
          name: name,
          hostname: host.hostname,
          user: host.user,
          port: host.port,
          status: Map.get(state.host_statuses, name, :unknown),
          last_check: Map.get(state.last_checks, name)
        }
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_cast({:update_hosts, hosts}, state) do
    # Initialize status for new hosts
    new_statuses =
      Enum.reduce(hosts, state.host_statuses, fn {name, _host}, acc ->
        Map.put_new(acc, name, :unknown)
      end)

    {:noreply, %{state | hosts: hosts, host_statuses: new_statuses}}
  end

  def handle_cast({:check_host, host_name}, state) do
    case Map.get(state.hosts, host_name) do
      nil ->
        {:noreply, state}

      host ->
        # Mark as checking
        state = put_status(state, host_name, :checking)
        broadcast_status(host_name, :checking)

        # Run check asynchronously
        parent = self()

        Task.start(fn ->
          result = perform_health_check(host)
          send(parent, {:check_result, host_name, result})
        end)

        {:noreply, state}
    end
  end

  def handle_cast(:check_all, state) do
    parent = self()

    # Mark all as checking and run checks concurrently
    state =
      Enum.reduce(state.hosts, state, fn {name, _host}, acc ->
        broadcast_status(name, :checking)
        put_status(acc, name, :checking)
      end)

    Task.start(fn ->
      state.hosts
      |> Task.async_stream(
        fn {name, host} ->
          result = perform_health_check(host)
          {name, result}
        end,
        max_concurrency: 10,
        timeout: @ssh_timeout + @tcp_timeout + 5_000
      )
      |> Enum.each(fn
        {:ok, {name, result}} -> send(parent, {:check_result, name, result})
        _ -> :ok
      end)
    end)

    {:noreply, state}
  end

  def handle_cast(:enable_monitoring, state) do
    if not state.enabled do
      schedule_check(state.check_interval)
    end

    {:noreply, %{state | enabled: true}}
  end

  def handle_cast(:disable_monitoring, state) do
    {:noreply, %{state | enabled: false}}
  end

  @impl true
  def handle_info({:check_result, host_name, status}, state) do
    state = put_status(state, host_name, status)
    state = put_in(state.last_checks[host_name], DateTime.utc_now())
    broadcast_status(host_name, status)
    {:noreply, state}
  end

  def handle_info(:periodic_check, state) do
    if state.enabled and map_size(state.hosts) > 0 do
      handle_cast(:check_all, state)
      schedule_check(state.check_interval)
      {:noreply, state}
    else
      if state.enabled, do: schedule_check(state.check_interval)
      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp perform_health_check(host) do
    # Step 1: TCP connectivity check
    case check_tcp(host.hostname, host.port) do
      :ok ->
        # Step 2: SSH connection check
        check_ssh(host)

      {:error, _reason} ->
        :tcp_failed
    end
  end

  defp check_tcp(hostname, port) do
    hostname_charlist = String.to_charlist(hostname)

    case :gen_tcp.connect(hostname_charlist, port, [], @tcp_timeout) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_ssh(host) do
    opts = [
      user: host.user || System.get_env("USER") || "root",
      port: host.port,
      timeout: @ssh_timeout,
      silently_accept_hosts: true
    ]

    opts =
      if host.identity do
        Keyword.put(opts, :identity, Path.expand(host.identity))
      else
        opts
      end

    case Connection.connect(host.hostname, opts) do
      {:ok, conn} ->
        # Step 3: Command execution check
        result = check_command(conn)
        Connection.close(conn)
        result

      {:error, :authentication_failed} ->
        :ssh_auth_failed

      {:error, :timeout} ->
        :ssh_timeout

      {:error, _reason} ->
        :ssh_auth_failed
    end
  end

  defp check_command(conn) do
    case Connection.exec(conn, "echo ok", timeout: 5_000) do
      {:ok, output, 0} ->
        if String.contains?(output, "ok"), do: :reachable, else: :command_failed

      _ ->
        :command_failed
    end
  end

  defp put_status(state, host_name, status) do
    put_in(state.host_statuses[host_name], status)
  end

  defp broadcast_status(host_name, status) do
    PubSub.broadcast(NexusWeb.PubSub, "hosts:status", {:host_status, host_name, status})
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :periodic_check, interval)
  end
end

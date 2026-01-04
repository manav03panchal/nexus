defmodule NexusWeb.DashboardLive do
  @moduledoc """
  Main dashboard LiveView for Nexus web interface.

  Provides interactive DAG visualization with real-time task execution
  status and log streaming.
  """

  use NexusWeb, :live_view

  alias Nexus.DAG
  alias Nexus.DSL.Parser
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    config_file = Application.get_env(:nexus, :web_config_file)

    socket =
      socket
      |> assign(:config_file, config_file)
      |> assign(:config, nil)
      |> assign(:graph, nil)
      |> assign(:dag_data, nil)
      |> assign(:selected_task, nil)
      |> assign(:task_statuses, %{})
      |> assign(:logs, [])
      |> assign(:execution_session, nil)
      |> assign(:error, nil)
      |> assign(:logs_expanded, false)

    if connected?(socket) do
      # Subscribe to execution updates
      PubSub.subscribe(NexusWeb.PubSub, "execution:updates")
      send(self(), :load_config)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"task_name" => task_name}, _uri, socket) do
    # Store the requested task name - we'll resolve it once config loads
    # Use String.to_atom since config may not be loaded yet
    task_atom = String.to_atom(task_name)

    IO.puts(
      "=== HANDLE_PARAMS: selected_task=#{task_atom}, config=#{socket.assigns.config != nil} ==="
    )

    {:noreply, assign(socket, :selected_task, task_atom)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :selected_task, nil)}
  end

  @impl true
  def handle_info(:load_config, socket) do
    IO.puts("\n=== LOAD_CONFIG MESSAGE RECEIVED ===")
    IO.puts("Config file: #{inspect(socket.assigns.config_file)}")

    case load_and_build_dag(socket.assigns.config_file) do
      {:ok, config, graph, dag_data} ->
        IO.puts("✓ Successfully loaded config")
        IO.puts("Tasks: #{map_size(config.tasks)}")
        IO.puts("DAG nodes: #{length(dag_data.nodes)}")
        IO.puts("DAG edges: #{length(dag_data.edges)}")

        task_statuses =
          config.tasks
          |> Map.keys()
          |> Map.new(fn name -> {name, :pending} end)

        {:noreply,
         socket
         |> assign(:config, config)
         |> assign(:graph, graph)
         |> assign(:dag_data, dag_data)
         |> assign(:task_statuses, task_statuses)
         |> assign(:error, nil)}

      {:error, reason} ->
        IO.puts("✗ Failed to load config: #{inspect(reason)}")
        {:noreply, assign(socket, :error, "Failed to load config: #{inspect(reason)}")}
    end
  end

  # Handle task events from broadcaster (map format)
  def handle_info({:task_started, %{task: task_name}}, socket) do
    task_statuses = Map.put(socket.assigns.task_statuses, task_name, :running)
    {:noreply, assign(socket, :task_statuses, task_statuses)}
  end

  def handle_info({:task_completed, %{task: task_name, success: true}}, socket) do
    task_statuses = Map.put(socket.assigns.task_statuses, task_name, :success)
    {:noreply, assign(socket, :task_statuses, task_statuses)}
  end

  def handle_info({:task_completed, %{task: task_name, success: false}}, socket) do
    task_statuses = Map.put(socket.assigns.task_statuses, task_name, :failed)
    {:noreply, assign(socket, :task_statuses, task_statuses)}
  end

  # Handle task events from execution session (atom format)
  def handle_info({:task_event, {:task_started, task_name}}, socket) when is_atom(task_name) do
    task_statuses = Map.put(socket.assigns.task_statuses, task_name, :running)
    {:noreply, assign(socket, :task_statuses, task_statuses)}
  end

  def handle_info({:task_event, {:task_completed, task_name, :ok}}, socket)
      when is_atom(task_name) do
    task_statuses = Map.put(socket.assigns.task_statuses, task_name, :success)
    {:noreply, assign(socket, :task_statuses, task_statuses)}
  end

  def handle_info({:task_event, {:task_completed, task_name, {:error, _}}}, socket)
      when is_atom(task_name) do
    task_statuses = Map.put(socket.assigns.task_statuses, task_name, :failed)
    {:noreply, assign(socket, :task_statuses, task_statuses)}
  end

  def handle_info({:task_skipped, task_name}, socket) do
    task_statuses = Map.put(socket.assigns.task_statuses, task_name, :skipped)
    {:noreply, assign(socket, :task_statuses, task_statuses)}
  end

  def handle_info({:log_line, line}, socket) do
    logs = socket.assigns.logs ++ [line]
    # Keep only last 500 lines
    logs = if length(logs) > 500, do: Enum.drop(logs, length(logs) - 500), else: logs
    {:noreply, assign(socket, :logs, logs)}
  end

  def handle_info({:execution_complete, _session_id}, socket) do
    {:noreply, assign(socket, :execution_session, nil)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_task", %{"task" => task_name}, socket) do
    task_atom = String.to_atom(task_name)

    IO.puts(
      "=== SELECT_TASK: selected_task=#{task_atom}, config=#{socket.assigns.config != nil} ==="
    )

    # Set selected_task directly AND push_patch to update URL
    socket = assign(socket, :selected_task, task_atom)
    {:noreply, push_patch(socket, to: "/task/#{task_name}", replace: true)}
  end

  def handle_event("close_panel", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_task, nil)
     |> push_patch(to: ~p"/")}
  end

  def handle_event("run_task", %{"task" => task_name}, socket) do
    task_atom = String.to_existing_atom(task_name)
    run_task(socket, task_atom)
  rescue
    ArgumentError ->
      {:noreply, put_flash(socket, :error, "Unknown task: #{task_name}")}
  end

  def handle_event("run_all", _params, socket) do
    run_all_tasks(socket)
  end

  def handle_event("stop_execution", _params, socket) do
    if socket.assigns.execution_session do
      NexusWeb.ExecutionSession.stop(socket.assigns.execution_session)
    end

    {:noreply, assign(socket, :execution_session, nil)}
  end

  def handle_event("clear_logs", _params, socket) do
    {:noreply, assign(socket, :logs, [])}
  end

  def handle_event("toggle_logs", _params, socket) do
    IO.puts(
      "=== TOGGLE LOGS CLICKED === expanded: #{socket.assigns.logs_expanded} -> #{not socket.assigns.logs_expanded}"
    )

    {:noreply, assign(socket, :logs_expanded, not socket.assigns.logs_expanded)}
  end

  def handle_event("reload_config", _params, socket) do
    send(self(), :load_config)
    {:noreply, socket}
  end

  defp load_and_build_dag(config_file) do
    with {:ok, config} <- Parser.parse_file(config_file),
         {:ok, graph} <- DAG.build(config) do
      dag_data = build_dag_data(config, graph)
      {:ok, config, graph, dag_data}
    end
  end

  defp build_dag_data(config, graph) do
    phases = DAG.execution_phases(graph)

    nodes =
      config.tasks
      |> Enum.with_index()
      |> Enum.map(fn {{name, task}, _index} ->
        phase = Enum.find_index(phases, fn p -> name in p end) || 0

        %{
          id: Atom.to_string(name),
          label: Atom.to_string(name),
          level: phase,
          title: task_tooltip(task),
          group: task_group(task)
        }
      end)

    edges =
      config.tasks
      |> Enum.flat_map(fn {name, task} ->
        Enum.map(task.deps, fn dep ->
          %{
            from: Atom.to_string(dep),
            to: Atom.to_string(name),
            arrows: "to"
          }
        end)
      end)

    %{nodes: nodes, edges: edges}
  end

  defp task_tooltip(task) do
    desc = Map.get(task, :description, "No description")
    hosts = Map.get(task, :hosts, []) |> Enum.join(", ")
    tags = Map.get(task, :tags, []) |> Enum.join(", ")

    """
    #{desc}
    Hosts: #{if hosts == "", do: "all", else: hosts}
    Tags: #{if tags == "", do: "none", else: tags}
    """
  end

  defp task_group(task) do
    cond do
      Map.get(task, :tags, []) |> Enum.member?("deploy") -> "deploy"
      Map.get(task, :tags, []) |> Enum.member?("test") -> "test"
      Map.get(task, :tags, []) |> Enum.member?("build") -> "build"
      true -> "default"
    end
  end

  defp run_task(socket, task_name) do
    if socket.assigns.execution_session do
      {:noreply, put_flash(socket, :error, "Execution already in progress")}
    else
      case NexusWeb.SessionSupervisor.start_session(
             socket.assigns.config_file,
             Atom.to_string(task_name),
             subscriber: self()
           ) do
        {:ok, session_id} ->
          # Reset task statuses
          task_statuses =
            socket.assigns.config.tasks
            |> Map.keys()
            |> Map.new(fn name -> {name, :pending} end)

          {:noreply,
           socket
           |> assign(:execution_session, session_id)
           |> assign(:task_statuses, task_statuses)
           |> assign(:logs, [])
           |> put_flash(:info, "Started execution of #{task_name}")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
      end
    end
  end

  defp run_all_tasks(socket) do
    if socket.assigns.execution_session do
      {:noreply, put_flash(socket, :error, "Execution already in progress")}
    else
      case NexusWeb.SessionSupervisor.start_session(
             socket.assigns.config_file,
             nil,
             subscriber: self()
           ) do
        {:ok, session_id} ->
          # Reset task statuses
          task_statuses =
            socket.assigns.config.tasks
            |> Map.keys()
            |> Map.new(fn name -> {name, :pending} end)

          {:noreply,
           socket
           |> assign(:execution_session, session_id)
           |> assign(:task_statuses, task_statuses)
           |> assign(:logs, [])
           |> put_flash(:info, "Started full pipeline execution")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-[#0a0a0a] text-gray-100">
      <!-- Main Content -->
      <div class="flex-1 flex flex-col overflow-hidden">
        <!-- Header -->
        <header class="bg-[#111] border-b border-[#222] px-6 py-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <img
                src="/assets/nexus-logo.png"
                alt="NEXUS"
                class="h-7"
                style="filter: drop-shadow(0 0 6px rgba(0,229,153,0.5));"
              />
              <span class="text-xs text-gray-500">
                {if @config_file, do: Path.basename(@config_file), else: "No config loaded"}
              </span>
            </div>
            <div class="flex items-center gap-3">
              <.button
                phx-click="reload_config"
                variant={:ghost}
                size={:sm}
              >
                <.icon name="hero-arrow-path" class="h-4 w-4 mr-1" /> Reload
              </.button>
              <%= if @execution_session do %>
                <.button
                  phx-click="stop_execution"
                  variant={:danger}
                  size={:sm}
                >
                  <.icon name="hero-stop" class="h-4 w-4 mr-1" /> Stop
                </.button>
              <% else %>
                <.button
                  phx-click="run_all"
                  variant={:primary}
                  size={:sm}
                  disabled={is_nil(@config)}
                >
                  <.icon name="hero-play" class="h-4 w-4 mr-1" /> Run All
                </.button>
              <% end %>
            </div>
          </div>
        </header>
        
    <!-- Main content area -->
        <div class="flex-1 flex flex-col overflow-hidden min-w-0">
          <!-- Top: DAG + Task Panel side by side -->
          <div class="flex-1 flex overflow-hidden min-w-0">
            <!-- DAG View -->
            <div id="dag-area" class="flex-1 relative min-w-0">
              <%= if @error do %>
                <div class="absolute inset-0 flex items-center justify-center">
                  <div class="bg-red-900/50 border border-red-500 p-6 max-w-md">
                    <h3 class="text-red-300 font-semibold mb-2">Error Loading Configuration</h3>
                    <p class="text-red-200 text-sm">{@error}</p>
                  </div>
                </div>
              <% else %>
                <%= if @dag_data do %>
                  <div
                    id="dag-container"
                    phx-hook="DagGraph"
                    phx-update="ignore"
                    data-nodes={Jason.encode!(@dag_data.nodes)}
                    data-edges={Jason.encode!(@dag_data.edges)}
                    data-statuses={
                      Jason.encode!(
                        @task_statuses
                        |> Enum.map(fn {k, v} -> {Atom.to_string(k), Atom.to_string(v)} end)
                        |> Map.new()
                      )
                    }
                    class="w-full h-full"
                  >
                  </div>
                <% else %>
                  <div class="absolute inset-0 flex items-center justify-center">
                    <.spinner class="h-8 w-8 text-[#00e599]" />
                  </div>
                <% end %>
              <% end %>
            </div>
            
    <!-- Task Panel -->
            <div id="panel-area">
              <%= if @selected_task && @config do %>
                <.task_panel
                  task={Map.get(@config.tasks, @selected_task)}
                  task_name={@selected_task}
                  status={Map.get(@task_statuses, @selected_task, :pending)}
                  graph={@graph}
                  executing={not is_nil(@execution_session)}
                />
              <% end %>
            </div>
          </div>
          
    <!-- Log Panel (Expandable) - OUTSIDE dag-area to avoid phx-update="ignore" issues -->
          <div
            id="log-panel"
            class="bg-[#0a0a0a] border-t border-[#222] flex flex-col flex-shrink-0 overflow-hidden"
            data-expanded={to_string(@logs_expanded)}
          >
            <div class="flex items-center justify-between px-4 py-2 bg-[#111] h-12 flex-shrink-0">
              <div class="flex items-center gap-2">
                <button
                  type="button"
                  phx-click="toggle_logs"
                  class="p-1 hover:bg-[#1a1a1a] transition-colors"
                >
                  <span class={[
                    "block transition-transform duration-200",
                    if(@logs_expanded, do: "rotate-180", else: "")
                  ]}>
                    <.icon name="hero-chevron-up" class="h-4 w-4 text-gray-400" />
                  </span>
                </button>
                <h3 class="text-sm font-medium text-gray-300">
                  Execution Logs
                  <%= if length(@logs) > 0 do %>
                    <span class="ml-2 px-1.5 py-0.5 bg-[#1a1a1a] text-xs text-gray-400">
                      {length(@logs)}
                    </span>
                  <% end %>
                </h3>
              </div>
              <div class="flex items-center gap-2">
                <.button phx-click="clear_logs" variant={:ghost} size={:sm}>
                  Clear
                </.button>
              </div>
            </div>
            <div
              id="log-stream"
              phx-hook="LogStream"
              class="flex-1 overflow-auto px-3 py-2 font-mono text-xs leading-tight bg-[#0a0a0a]"
            >
              <%= if Enum.empty?(@logs) do %>
                <p class="text-gray-500 italic py-2">No logs yet. Run a task to see output.</p>
              <% else %>
                <pre class="whitespace-pre-wrap"><%= for {line, idx} <- Enum.with_index(@logs) do %><code id={"log-#{idx}"} class={log_line_class(line)}>{line.content}
    </code><% end %></pre>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp log_line_class(%{type: :stderr}), do: "text-red-400"
  defp log_line_class(%{type: :info}), do: "text-blue-400"
  defp log_line_class(%{type: :success}), do: "text-emerald-400"
  defp log_line_class(_), do: "text-gray-300"

  defp format_command(%{cmd: cmd}), do: cmd
  defp format_command(cmd) when is_binary(cmd), do: cmd
  defp format_command(cmd), do: inspect(cmd)

  attr :task, :map, required: true
  attr :task_name, :atom, required: true
  attr :status, :atom, required: true
  attr :graph, :any, required: true
  attr :executing, :boolean, required: true

  defp task_panel(assigns) do
    deps =
      if assigns.graph, do: DAG.direct_dependencies(assigns.graph, assigns.task_name), else: []

    dependents =
      if assigns.graph, do: DAG.direct_dependents(assigns.graph, assigns.task_name), else: []

    assigns = assign(assigns, :deps, deps)
    assigns = assign(assigns, :dependents, dependents)

    ~H"""
    <div id="task-panel" class="w-96 bg-[#111] border-l border-[#222] flex flex-col h-full">
      <div class="flex items-center justify-between px-4 py-3 border-b border-[#222]">
        <div class="flex items-center gap-3">
          <h2 class="font-semibold text-white">{@task_name}</h2>
          <.status_badge status={@status} />
        </div>
        <button
          type="button"
          phx-click="close_panel"
          class="text-gray-400 hover:text-white transition-colors"
        >
          <.icon name="hero-x-mark" class="h-5 w-5" />
        </button>
      </div>

      <div class="flex-1 overflow-auto p-4 space-y-6">
        <!-- Description -->
        <div>
          <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-2">
            Description
          </h3>
          <p class="text-sm text-gray-300">
            {Map.get(@task, :description) || "No description provided"}
          </p>
        </div>
        
    <!-- Hosts -->
        <div>
          <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-2">
            Hosts
          </h3>
          <div class="flex flex-wrap gap-1">
            <%= if hosts = Map.get(@task, :hosts, []) do %>
              <%= if Enum.empty?(hosts) do %>
                <span class="text-sm text-gray-500 italic">All hosts</span>
              <% else %>
                <%= for host <- hosts do %>
                  <span class="px-2 py-0.5 bg-[#1a1a1a] border border-[#333] text-xs text-gray-300">
                    {host}
                  </span>
                <% end %>
              <% end %>
            <% end %>
          </div>
        </div>
        
    <!-- Tags -->
        <div>
          <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-2">
            Tags
          </h3>
          <div class="flex flex-wrap gap-1">
            <%= if tags = Map.get(@task, :tags, []) do %>
              <%= if Enum.empty?(tags) do %>
                <span class="text-sm text-gray-500 italic">No tags</span>
              <% else %>
                <%= for tag <- tags do %>
                  <span class="px-2 py-0.5 bg-[#00e599]/10 border border-[#00e599]/30 text-xs text-[#00e599]">
                    {tag}
                  </span>
                <% end %>
              <% end %>
            <% end %>
          </div>
        </div>
        
    <!-- Dependencies -->
        <div>
          <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-2">
            Dependencies
          </h3>
          <div class="flex flex-wrap gap-1">
            <%= if Enum.empty?(@deps) do %>
              <span class="text-sm text-gray-500 italic">No dependencies</span>
            <% else %>
              <%= for dep <- @deps do %>
                <button
                  type="button"
                  phx-click="select_task"
                  phx-value-task={dep}
                  class="px-2 py-0.5 bg-[#1a1a1a] border border-[#333] hover:border-[#00e599]/50 text-xs text-gray-300 transition-colors"
                >
                  {dep}
                </button>
              <% end %>
            <% end %>
          </div>
        </div>
        
    <!-- Dependents -->
        <div>
          <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-2">
            Dependents
          </h3>
          <div class="flex flex-wrap gap-1">
            <%= if Enum.empty?(@dependents) do %>
              <span class="text-sm text-gray-500 italic">No dependents</span>
            <% else %>
              <%= for dep <- @dependents do %>
                <button
                  type="button"
                  phx-click="select_task"
                  phx-value-task={dep}
                  class="px-2 py-0.5 bg-[#1a1a1a] border border-[#333] hover:border-[#00e599]/50 text-xs text-gray-300 transition-colors"
                >
                  {dep}
                </button>
              <% end %>
            <% end %>
          </div>
        </div>
        
    <!-- Commands -->
        <div>
          <h3 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-2">
            Commands
          </h3>
          <div class="space-y-2">
            <%= if commands = Map.get(@task, :commands, []) do %>
              <%= if Enum.empty?(commands) do %>
                <span class="text-sm text-gray-500 italic">No commands</span>
              <% else %>
                <%= for cmd <- commands do %>
                  <div class="bg-[#0a0a0a] border border-[#222] p-2 font-mono text-xs text-[#00e599] overflow-x-auto">
                    <code>{format_command(cmd)}</code>
                  </div>
                <% end %>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
      
    <!-- Actions -->
      <div class="p-4 border-t border-[#222]">
        <.button
          phx-click="run_task"
          phx-value-task={@task_name}
          variant={:primary}
          class="w-full"
          disabled={@executing}
        >
          <%= if @executing do %>
            <.spinner class="h-4 w-4 mr-2" /> Executing...
          <% else %>
            <.icon name="hero-play" class="h-4 w-4 mr-2" /> Run Task
          <% end %>
        </.button>
      </div>
    </div>
    """
  end
end

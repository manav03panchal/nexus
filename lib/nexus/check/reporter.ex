defmodule Nexus.Check.Reporter do
  @moduledoc """
  Formats and prints check mode output.

  Displays what changes would be made without actually executing them.
  """

  alias Nexus.Check.Differ
  alias Nexus.Resources.Types.Command, as: ResourceCommand
  alias Nexus.Resources.Types.{Directory, File, Group, Package, Service, User}
  alias Nexus.Types.{Command, Download, Template, Upload, WaitFor}

  @type check_result :: %{
          task: atom(),
          host: String.t(),
          command_type: atom(),
          description: String.t(),
          diff: Differ.diff() | nil,
          action:
            :would_run
            | :would_upload
            | :would_download
            | :would_render
            | :would_wait
            | :would_change
        }

  @doc """
  Prints the check mode header.
  """
  @spec print_header() :: :ok
  def print_header do
    IO.puts("")
    IO.puts(String.duplicate("=", 60))
    IO.puts("                     CHECK MODE")
    IO.puts("              No changes will be made")
    IO.puts(String.duplicate("=", 60))
    IO.puts("")
    :ok
  end

  @doc """
  Prints a task's check results.
  """
  @spec print_task_check(atom(), [String.t()], [check_result()]) :: :ok
  def print_task_check(task_name, hosts, results) do
    hosts_str = Enum.join(hosts, ", ")
    IO.puts("Task: :#{task_name} [#{hosts_str}]")
    IO.puts("")

    Enum.each(results, &print_check_result/1)

    IO.puts("")
    :ok
  end

  @doc """
  Prints a summary of all checks.
  """
  @spec print_summary(integer(), integer(), integer()) :: :ok
  def print_summary(tasks, hosts, changes) do
    IO.puts(String.duplicate("=", 60))
    IO.puts("Summary: #{tasks} tasks, #{hosts} hosts, #{changes} changes")
    IO.puts("Run without --check to apply changes.")
    IO.puts("")
    :ok
  end

  @doc """
  Generates check results for a command.
  """
  @spec check_command(any(), String.t(), map()) :: check_result()
  def check_command(%Command{} = cmd, host, _context) do
    %{
      task: nil,
      host: host,
      command_type: :run,
      description: "$ #{cmd.cmd}",
      diff: nil,
      action: :would_run
    }
  end

  def check_command(%Upload{} = upload, host, _context) do
    %{
      task: nil,
      host: host,
      command_type: :upload,
      description: "upload #{upload.local_path} -> #{upload.remote_path}",
      diff: nil,
      action: :would_upload
    }
  end

  def check_command(%Download{} = download, host, _context) do
    %{
      task: nil,
      host: host,
      command_type: :download,
      description: "download #{download.remote_path} -> #{download.local_path}",
      diff: nil,
      action: :would_download
    }
  end

  def check_command(%Template{} = template, host, context) do
    diff = compute_template_diff(template, context)

    %{
      task: nil,
      host: host,
      command_type: :template,
      description: "template #{template.source} -> #{template.destination}",
      diff: diff,
      action: :would_render
    }
  end

  def check_command(%WaitFor{} = wait_for, host, _context) do
    %{
      task: nil,
      host: host,
      command_type: :wait_for,
      description: "wait_for :#{wait_for.type} #{wait_for.target}",
      diff: nil,
      action: :would_wait
    }
  end

  # Resource types
  def check_command(%ResourceCommand{} = cmd, host, _context) do
    guards = []
    guards = if cmd.creates, do: ["creates=#{cmd.creates}" | guards], else: guards
    guards = if cmd.removes, do: ["removes=#{cmd.removes}" | guards], else: guards
    guards = if cmd.unless, do: ["unless=#{cmd.unless}" | guards], else: guards
    guards = if cmd.onlyif, do: ["onlyif=#{cmd.onlyif}" | guards], else: guards

    desc =
      if guards == [] do
        "$ #{cmd.cmd}"
      else
        "$ #{cmd.cmd} (#{Enum.join(Enum.reverse(guards), ", ")})"
      end

    %{
      task: nil,
      host: host,
      command_type: :command,
      description: desc,
      diff: nil,
      action: :would_run
    }
  end

  def check_command(%File{} = file, host, _context) do
    state_desc = if file.state == :present, do: "create/update", else: "remove"

    %{
      task: nil,
      host: host,
      command_type: :file,
      description: "file[#{file.path}] #{state_desc}",
      diff: nil,
      action: :would_change
    }
  end

  def check_command(%Directory{} = dir, host, _context) do
    state_desc = if dir.state == :present, do: "create", else: "remove"

    %{
      task: nil,
      host: host,
      command_type: :directory,
      description: "directory[#{dir.path}] #{state_desc}",
      diff: nil,
      action: :would_change
    }
  end

  def check_command(%Package{} = pkg, host, _context) do
    state_desc =
      case pkg.state do
        :present -> "install"
        :absent -> "remove"
        :latest -> "upgrade"
      end

    %{
      task: nil,
      host: host,
      command_type: :package,
      description: "package[#{pkg.name}] #{state_desc}",
      diff: nil,
      action: :would_change
    }
  end

  def check_command(%Service{} = svc, host, _context) do
    actions = []
    actions = if svc.state, do: ["state=#{svc.state}" | actions], else: actions
    actions = if svc.enabled != nil, do: ["enabled=#{svc.enabled}" | actions], else: actions
    desc = Enum.join(Enum.reverse(actions), ", ")

    %{
      task: nil,
      host: host,
      command_type: :service,
      description: "service[#{svc.name}] #{desc}",
      diff: nil,
      action: :would_change
    }
  end

  def check_command(%User{} = user, host, _context) do
    state_desc = if user.state == :present, do: "create/update", else: "remove"

    %{
      task: nil,
      host: host,
      command_type: :user,
      description: "user[#{user.name}] #{state_desc}",
      diff: nil,
      action: :would_change
    }
  end

  def check_command(%Group{} = group, host, _context) do
    state_desc = if group.state == :present, do: "create", else: "remove"

    %{
      task: nil,
      host: host,
      command_type: :group,
      description: "group[#{group.name}] #{state_desc}",
      diff: nil,
      action: :would_change
    }
  end

  @doc """
  Computes what a template would render to.
  """
  # sobelow_skip ["RCE.EEx"]
  @spec render_template_preview(Template.t()) :: {:ok, String.t()} | {:error, term()}
  def render_template_preview(%Template{} = template) do
    case Elixir.File.read(template.source) do
      {:ok, content} ->
        try do
          bindings =
            template.vars
            |> Enum.map(fn {k, v} -> {k, v} end)

          rendered = EEx.eval_string(content, assigns: bindings)
          {:ok, rendered}
        rescue
          e -> {:error, Exception.message(e)}
        end

      {:error, reason} ->
        {:error, "Cannot read template: #{:file.format_error(reason)}"}
    end
  end

  # Private functions

  defp print_check_result(result) do
    action_icon =
      case result.action do
        :would_run -> ">"
        :would_upload -> "^"
        :would_download -> "v"
        :would_render -> "~"
        :would_wait -> "?"
        :would_change -> "*"
      end

    IO.puts("  [#{action_icon}] #{result.description}")

    if result.diff && Differ.has_changes?(result.diff) do
      print_diff(result.diff)
    end
  end

  defp print_diff(diff) do
    IO.puts("")

    diff
    |> Enum.take(20)
    |> Enum.each(fn
      {:eq, line} -> IO.puts("      #{line}")
      {:del, line} -> IO.puts("    - #{line}")
      {:ins, line} -> IO.puts("    + #{line}")
    end)

    remaining = length(diff) - 20

    if remaining > 0 do
      IO.puts("      ... (#{remaining} more lines)")
    end

    IO.puts("")
  end

  defp compute_template_diff(%Template{} = template, context) do
    # Try to get the current remote content from context
    current_content = Map.get(context, :current_content, "")

    case render_template_preview(template) do
      {:ok, new_content} ->
        Differ.diff_text(current_content, new_content)

      {:error, _} ->
        nil
    end
  end
end

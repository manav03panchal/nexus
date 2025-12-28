defmodule Nexus.Generators do
  @moduledoc """
  StreamData generators for property-based testing.
  """

  use ExUnitProperties

  @doc """
  Generates valid task names (atoms).
  """
  def task_name do
    gen all(
          name <- atom(:alphanumeric),
          name != nil
        ) do
      name
    end
  end

  @doc """
  Generates valid hostnames.
  """
  def hostname do
    gen all(
          segments <-
            list_of(string(:alphanumeric, min_length: 1, max_length: 12),
              min_length: 1,
              max_length: 4
            )
        ) do
      Enum.join(segments, ".")
    end
  end

  @doc """
  Generates valid usernames.
  """
  def username do
    string(:alphanumeric, min_length: 1, max_length: 32)
  end

  @doc """
  Generates valid port numbers.
  """
  def port do
    integer(1..65_535)
  end

  @doc """
  Generates host strings in various formats:
  - hostname
  - user@hostname
  - user@hostname:port
  """
  def host_string do
    gen all(
          host <- hostname(),
          format <- member_of([:simple, :with_user, :with_user_and_port]),
          user <- username(),
          port <- port()
        ) do
      case format do
        :simple -> host
        :with_user -> "#{user}@#{host}"
        :with_user_and_port -> "#{user}@#{host}:#{port}"
      end
    end
  end

  @doc """
  Generates valid command strings.
  """
  def command do
    gen all(cmd <- string(:printable, min_length: 1, max_length: 256)) do
      String.trim(cmd)
    end
  end

  @doc """
  Generates a list of task names for dependency testing.
  """
  def task_deps(max_deps \\ 5) do
    list_of(task_name(), max_length: max_deps)
  end

  @doc """
  Generates a complete task definition map.
  """
  def task_definition do
    gen all(
          name <- task_name(),
          deps <- task_deps(3),
          timeout <- positive_integer(),
          strategy <- member_of([:parallel, :serial])
        ) do
      %{
        name: name,
        deps: deps,
        timeout: timeout,
        strategy: strategy,
        commands: []
      }
    end
  end
end

defmodule Nexus.TestCase do
  @moduledoc """
  Base test case for Nexus tests.

  Provides common setup and helper functions for all test types.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Nexus.TestCase
    end
  end

  @doc """
  Creates a temporary directory for test files.
  Returns the path and cleans up after the test.
  """
  def tmp_dir(context) do
    path = Path.join(System.tmp_dir!(), "nexus_test_#{context.test}")
    File.mkdir_p!(path)

    on_exit(fn ->
      File.rm_rf!(path)
    end)

    {:ok, tmp_dir: path}
  end

  @doc """
  Creates a test nexus.exs file with the given content.
  """
  def create_nexus_file(dir, content) do
    path = Path.join(dir, "nexus.exs")
    File.write!(path, content)
    path
  end

  @doc """
  Waits for a condition to be true, with timeout.
  """
  def wait_until(fun, timeout \\ 5000, interval \\ 100) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(fun, deadline, interval)
  end

  defp do_wait_until(fun, deadline, interval) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        {:error, :timeout}
      else
        Process.sleep(interval)
        do_wait_until(fun, deadline, interval)
      end
    end
  end
end

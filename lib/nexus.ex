defmodule Nexus do
  @moduledoc """
  Nexus - A distributed task runner unifying Make, Ansible, and CI/CD.

  Nexus provides a single, consistent interface for:
  - Local and remote command execution
  - DAG-based task dependencies
  - SSH connection pooling
  - Pipeline orchestration

  ## Quick Start

      # Define tasks in nexus.exs
      task :build do
        run "mix compile"
      end

      task :test, deps: [:build] do
        run "mix test"
      end

      # Execute
      $ nexus run test
  """

  @version Mix.Project.config()[:version]

  @doc """
  Returns the current version of Nexus.
  """
  @spec version() :: String.t()
  def version, do: @version
end

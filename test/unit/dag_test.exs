defmodule Nexus.DAGTest do
  use ExUnit.Case, async: true

  # Tests will be added in Phase 3
  @moduletag :unit

  describe "build/1" do
    @tag :skip
    test "builds graph from tasks with deps" do
      # Phase 3: DAG implementation
    end
  end

  describe "topological_sort/1" do
    @tag :skip
    test "produces valid execution order" do
      # Phase 3: DAG implementation
    end
  end
end

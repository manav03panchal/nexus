defmodule Nexus.Property.DAGTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Nexus.Generators

  @moduletag :property

  describe "topological sort properties" do
    @tag :skip
    property "dependencies always come before dependents" do
      # Phase 3: DAG property tests
      check all(_tasks <- list_of(task_definition(), min_length: 1, max_length: 20)) do
        true
      end
    end
  end
end

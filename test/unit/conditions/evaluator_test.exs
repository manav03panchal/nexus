defmodule Nexus.Conditions.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Nexus.Conditions.Evaluator

  @context %{
    host_id: :web1,
    facts: %{
      os: :linux,
      os_family: :debian,
      cpu_count: 4,
      memory_mb: 8192,
      arch: :x86_64,
      hostname: "web1"
    }
  }

  describe "evaluate/2 with boolean values" do
    test "true always evaluates to true" do
      assert Evaluator.evaluate(true, @context) == true
    end

    test "false always evaluates to false" do
      assert Evaluator.evaluate(false, @context) == false
    end

    test "nil evaluates to true (no condition)" do
      assert Evaluator.evaluate(nil, @context) == true
    end
  end

  describe "evaluate/2 with fact references" do
    test "resolves fact value from context" do
      assert Evaluator.evaluate({:nexus_fact, :os}, @context) == :linux
      assert Evaluator.evaluate({:nexus_fact, :cpu_count}, @context) == 4
    end

    test "returns nil for missing fact" do
      assert Evaluator.evaluate({:nexus_fact, :nonexistent}, @context) == nil
    end
  end

  describe "evaluate/2 with equality comparisons" do
    test "equality with matching values returns true" do
      condition = {:==, {:nexus_fact, :os}, :linux}
      assert Evaluator.evaluate(condition, @context) == true
    end

    test "equality with non-matching values returns false" do
      condition = {:==, {:nexus_fact, :os}, :darwin}
      assert Evaluator.evaluate(condition, @context) == false
    end

    test "inequality with non-matching values returns true" do
      condition = {:!=, {:nexus_fact, :os}, :darwin}
      assert Evaluator.evaluate(condition, @context) == true
    end

    test "inequality with matching values returns false" do
      condition = {:!=, {:nexus_fact, :os}, :linux}
      assert Evaluator.evaluate(condition, @context) == false
    end
  end

  describe "evaluate/2 with numeric comparisons" do
    test "greater than comparison" do
      assert Evaluator.evaluate({:>, {:nexus_fact, :cpu_count}, 2}, @context) == true
      assert Evaluator.evaluate({:>, {:nexus_fact, :cpu_count}, 4}, @context) == false
    end

    test "less than comparison" do
      assert Evaluator.evaluate({:<, {:nexus_fact, :cpu_count}, 8}, @context) == true
      assert Evaluator.evaluate({:<, {:nexus_fact, :cpu_count}, 2}, @context) == false
    end

    test "greater than or equal comparison" do
      assert Evaluator.evaluate({:>=, {:nexus_fact, :cpu_count}, 4}, @context) == true
      assert Evaluator.evaluate({:>=, {:nexus_fact, :cpu_count}, 5}, @context) == false
    end

    test "less than or equal comparison" do
      assert Evaluator.evaluate({:<=, {:nexus_fact, :cpu_count}, 4}, @context) == true
      assert Evaluator.evaluate({:<=, {:nexus_fact, :cpu_count}, 3}, @context) == false
    end
  end

  describe "evaluate/2 with logical operators" do
    test "and with both true returns true" do
      condition =
        {:and, {:==, {:nexus_fact, :os}, :linux}, {:==, {:nexus_fact, :os_family}, :debian}}

      assert Evaluator.evaluate(condition, @context) == true
    end

    test "and with one false returns false" do
      condition =
        {:and, {:==, {:nexus_fact, :os}, :linux}, {:==, {:nexus_fact, :os_family}, :rhel}}

      assert Evaluator.evaluate(condition, @context) == false
    end

    test "or with one true returns true" do
      condition =
        {:or, {:==, {:nexus_fact, :os}, :darwin}, {:==, {:nexus_fact, :os_family}, :debian}}

      assert Evaluator.evaluate(condition, @context) == true
    end

    test "or with both false returns false" do
      condition =
        {:or, {:==, {:nexus_fact, :os}, :darwin}, {:==, {:nexus_fact, :os_family}, :rhel}}

      assert Evaluator.evaluate(condition, @context) == false
    end

    test "not inverts boolean value" do
      assert Evaluator.evaluate({:not, {:==, {:nexus_fact, :os}, :linux}}, @context) == false
      assert Evaluator.evaluate({:not, {:==, {:nexus_fact, :os}, :darwin}}, @context) == true
    end
  end

  describe "evaluate/2 with in operator" do
    test "in returns true when value is in list" do
      condition = {:in, {:nexus_fact, :os}, [:linux, :darwin]}
      assert Evaluator.evaluate(condition, @context) == true
    end

    test "in returns false when value is not in list" do
      condition = {:in, {:nexus_fact, :os}, [:windows, :freebsd]}
      assert Evaluator.evaluate(condition, @context) == false
    end
  end

  describe "evaluate/2 with nested conditions" do
    test "evaluates complex nested conditions" do
      # (os == :linux AND cpu_count >= 4) OR memory_mb > 16000
      condition =
        {:or, {:and, {:==, {:nexus_fact, :os}, :linux}, {:>=, {:nexus_fact, :cpu_count}, 4}},
         {:>, {:nexus_fact, :memory_mb}, 16_000}}

      assert Evaluator.evaluate(condition, @context) == true
    end
  end

  describe "evaluate/2 with literal values" do
    test "evaluates literal strings" do
      assert Evaluator.evaluate("literal", @context) == "literal"
    end

    test "evaluates literal atoms" do
      assert Evaluator.evaluate(:some_atom, @context) == :some_atom
    end

    test "evaluates literal integers" do
      assert Evaluator.evaluate(42, @context) == 42
    end

    test "evaluates literal lists" do
      assert Evaluator.evaluate([1, 2, 3], @context) == [1, 2, 3]
    end
  end

  describe "build_context/2" do
    test "creates context with host_id and facts" do
      facts = %{os: :linux}
      context = Evaluator.build_context(:my_host, facts)

      assert context.host_id == :my_host
      assert context.facts == facts
    end

    test "defaults to empty facts" do
      context = Evaluator.build_context(:my_host)

      assert context.host_id == :my_host
      assert context.facts == %{}
    end
  end

  describe "parse_condition/1" do
    test "extracts when option" do
      opts = [sudo: true, when: {:==, {:nexus_fact, :os}, :linux}]
      condition = Evaluator.parse_condition(opts)

      assert condition == {:==, {:nexus_fact, :os}, :linux}
    end

    test "defaults to true when when option missing" do
      opts = [sudo: true]
      condition = Evaluator.parse_condition(opts)

      assert condition == true
    end
  end
end

defmodule Nexus.Conditions.Evaluator do
  @moduledoc """
  Evaluates conditional expressions for the `when:` option.

  Conditions are evaluated at runtime with access to facts and environment
  variables. They support comparison operators and boolean logic.

  ## Supported Expressions

    * Comparisons: `==`, `!=`, `<`, `>`, `<=`, `>=`
    * Boolean: `and`, `or`, `not`
    * Membership: `in`
    * Facts: `{:nexus_fact, :name}` placeholders
    * Literals: atoms, strings, integers, booleans

  ## Examples

      # Simple comparison
      facts(:os) == :linux

      # Boolean logic
      facts(:os_family) == :debian and facts(:arch) == :x86_64

      # Environment check
      env("ENV") == "production"

      # Membership
      facts(:os_family) in [:debian, :ubuntu]

  """

  alias Nexus.Facts.Cache

  @type condition :: term()
  @type context :: %{
          host_id: atom() | String.t(),
          facts: map()
        }

  @doc """
  Evaluates a condition in the given context.

  Returns `true` if the condition passes, `false` otherwise.
  A `nil` or missing condition always returns `true`.
  """
  @spec evaluate(condition(), context()) :: boolean()
  def evaluate(nil, _context), do: true
  def evaluate(true, _context), do: true
  def evaluate(false, _context), do: false

  # Resolve fact placeholders
  def evaluate({:nexus_fact, fact_name}, context) do
    get_fact(context, fact_name)
  end

  # Boolean operators
  def evaluate({:and, left, right}, context) do
    evaluate(left, context) and evaluate(right, context)
  end

  def evaluate({:or, left, right}, context) do
    evaluate(left, context) or evaluate(right, context)
  end

  def evaluate({:not, expr}, context) do
    not evaluate(expr, context)
  end

  # Comparison operators
  def evaluate({:==, left, right}, context) do
    resolve_value(left, context) == resolve_value(right, context)
  end

  def evaluate({:!=, left, right}, context) do
    resolve_value(left, context) != resolve_value(right, context)
  end

  def evaluate({:<, left, right}, context) do
    resolve_value(left, context) < resolve_value(right, context)
  end

  def evaluate({:>, left, right}, context) do
    resolve_value(left, context) > resolve_value(right, context)
  end

  def evaluate({:<=, left, right}, context) do
    resolve_value(left, context) <= resolve_value(right, context)
  end

  def evaluate({:>=, left, right}, context) do
    resolve_value(left, context) >= resolve_value(right, context)
  end

  # Membership operator
  def evaluate({:in, element, list}, context) do
    resolved_element = resolve_value(element, context)
    resolved_list = resolve_value(list, context)
    resolved_element in resolved_list
  end

  # Literal values pass through
  def evaluate(value, _context) when is_atom(value), do: value
  def evaluate(value, _context) when is_binary(value), do: value
  def evaluate(value, _context) when is_integer(value), do: value
  def evaluate(value, _context) when is_float(value), do: value
  def evaluate(value, _context) when is_list(value), do: value

  @doc """
  Resolves a value in the given context.

  Handles fact placeholders and literal values.
  """
  @spec resolve_value(term(), context()) :: term()
  def resolve_value({:nexus_fact, fact_name}, context) do
    get_fact(context, fact_name)
  end

  def resolve_value(list, context) when is_list(list) do
    Enum.map(list, &resolve_value(&1, context))
  end

  def resolve_value(value, _context), do: value

  @doc """
  Creates an evaluation context for a host.
  """
  @spec build_context(atom() | String.t(), map()) :: context()
  def build_context(host_id, facts \\ %{}) do
    %{
      host_id: host_id,
      facts: facts
    }
  end

  @doc """
  Parses a condition from DSL options.

  The `when:` option can be:
    * `true` / `false` - literal boolean
    * A comparison expression
    * A boolean combination of expressions
  """
  @spec parse_condition(keyword()) :: condition()
  def parse_condition(opts) do
    Keyword.get(opts, :when, true)
  end

  # Get a fact from context or cache
  defp get_fact(context, fact_name) do
    case Map.get(context.facts, fact_name) do
      nil ->
        # Try the cache if not in context
        Cache.get(context.host_id, fact_name)

      value ->
        value
    end
  end
end

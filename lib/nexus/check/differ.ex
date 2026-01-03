defmodule Nexus.Check.Differ do
  @moduledoc """
  Computes differences for check mode.

  Handles template diffs, file comparisons, and change previews.
  """

  @type diff_line :: {:eq, String.t()} | {:ins, String.t()} | {:del, String.t()}
  @type diff :: [diff_line()]

  @doc """
  Computes a line-by-line diff between two strings.

  Returns a list of tagged lines:
    * `{:eq, line}` - Line is the same in both
    * `{:del, line}` - Line was deleted (in old but not new)
    * `{:ins, line}` - Line was inserted (in new but not old)
  """
  @spec diff_text(String.t(), String.t()) :: diff()
  def diff_text(old, new) do
    old_lines = String.split(old, "\n")
    new_lines = String.split(new, "\n")

    compute_diff(old_lines, new_lines)
  end

  @doc """
  Formats a diff as a unified diff string.
  """
  @spec format_unified(diff(), keyword()) :: String.t()
  def format_unified(diff, opts \\ []) do
    context = Keyword.get(opts, :context, 3)
    old_name = Keyword.get(opts, :old_name, "current")
    new_name = Keyword.get(opts, :new_name, "proposed")

    # Group diff into hunks
    hunks = create_hunks(diff, context)

    header = """
    --- #{old_name}
    +++ #{new_name}
    """

    hunk_text = Enum.map_join(hunks, "\n", &format_hunk/1)

    header <> hunk_text
  end

  @doc """
  Checks if a diff contains any changes.
  """
  @spec has_changes?(diff()) :: boolean()
  def has_changes?(diff) do
    Enum.any?(diff, fn
      {:ins, _} -> true
      {:del, _} -> true
      _ -> false
    end)
  end

  @doc """
  Counts the number of changes in a diff.
  """
  @spec count_changes(diff()) :: {non_neg_integer(), non_neg_integer()}
  def count_changes(diff) do
    Enum.reduce(diff, {0, 0}, fn
      {:ins, _}, {ins, del} -> {ins + 1, del}
      {:del, _}, {ins, del} -> {ins, del + 1}
      _, acc -> acc
    end)
  end

  # Simple line-based diff using Myers algorithm (simplified LCS)
  defp compute_diff(old_lines, new_lines) do
    lcs = longest_common_subsequence(old_lines, new_lines)
    build_diff(old_lines, new_lines, lcs, 0, 0, [])
  end

  defp longest_common_subsequence([], _), do: []
  defp longest_common_subsequence(_, []), do: []

  defp longest_common_subsequence([h | t1], [h | t2]) do
    [h | longest_common_subsequence(t1, t2)]
  end

  defp longest_common_subsequence([_ | t1] = l1, [_ | t2] = l2) do
    lcs1 = longest_common_subsequence(t1, l2)
    lcs2 = longest_common_subsequence(l1, t2)

    if length(lcs1) > length(lcs2), do: lcs1, else: lcs2
  end

  defp build_diff([], [], _, _, _, acc), do: Enum.reverse(acc)

  defp build_diff([h | old], [h | new], [h | lcs], old_idx, new_idx, acc) do
    build_diff(old, new, lcs, old_idx + 1, new_idx + 1, [{:eq, h} | acc])
  end

  defp build_diff([h | old], new, lcs, old_idx, new_idx, acc) when lcs == [] or hd(lcs) != h do
    build_diff(old, new, lcs, old_idx + 1, new_idx, [{:del, h} | acc])
  end

  defp build_diff(old, [h | new], lcs, old_idx, new_idx, acc) do
    build_diff(old, new, lcs, old_idx, new_idx + 1, [{:ins, h} | acc])
  end

  # Create hunks from diff with context lines
  defp create_hunks(diff, context) do
    indexed = Enum.with_index(diff)

    # Find positions of changes
    change_positions =
      indexed
      |> Enum.filter(fn {{type, _}, _} -> type in [:ins, :del] end)
      |> Enum.map(fn {_, idx} -> idx end)

    if Enum.empty?(change_positions) do
      []
    else
      # Group nearby changes into hunks
      group_into_hunks(change_positions, indexed, context)
    end
  end

  defp group_into_hunks(positions, indexed, context) do
    # Simple grouping: merge positions within 2*context of each other
    groups =
      Enum.reduce(positions, [], fn pos, acc ->
        case acc do
          [] ->
            [[pos]]

          [[last | _] = group | rest] when pos - last <= 2 * context ->
            [[pos | group] | rest]

          _ ->
            [[pos] | acc]
        end
      end)
      |> Enum.map(&Enum.reverse/1)
      |> Enum.reverse()

    # Convert groups to hunks
    Enum.map(groups, fn group ->
      start_pos = max(0, Enum.min(group) - context)
      end_pos = min(length(indexed) - 1, Enum.max(group) + context)

      lines =
        indexed
        |> Enum.slice(start_pos..end_pos)
        |> Enum.map(fn {line, _} -> line end)

      %{
        old_start: count_old_lines_before(indexed, start_pos) + 1,
        new_start: count_new_lines_before(indexed, start_pos) + 1,
        lines: lines
      }
    end)
  end

  defp count_old_lines_before(indexed, pos) do
    indexed
    |> Enum.take(pos)
    |> Enum.count(fn {{type, _}, _} -> type in [:eq, :del] end)
  end

  defp count_new_lines_before(indexed, pos) do
    indexed
    |> Enum.take(pos)
    |> Enum.count(fn {{type, _}, _} -> type in [:eq, :ins] end)
  end

  defp format_hunk(%{old_start: old_start, new_start: new_start, lines: lines}) do
    old_count = Enum.count(lines, fn {type, _} -> type in [:eq, :del] end)
    new_count = Enum.count(lines, fn {type, _} -> type in [:eq, :ins] end)

    header = "@@ -#{old_start},#{old_count} +#{new_start},#{new_count} @@"

    body =
      Enum.map_join(lines, "\n", fn
        {:eq, line} -> " #{line}"
        {:del, line} -> "-#{line}"
        {:ins, line} -> "+#{line}"
      end)

    header <> "\n" <> body
  end
end

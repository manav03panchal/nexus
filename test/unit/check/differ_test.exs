defmodule Nexus.Check.DifferTest do
  use ExUnit.Case, async: true

  alias Nexus.Check.Differ

  describe "diff_text/2" do
    test "returns empty list of changes for identical texts" do
      text = "line1\nline2\nline3"
      diff = Differ.diff_text(text, text)

      # All lines should be equal
      assert Enum.all?(diff, fn {type, _} -> type == :eq end)
    end

    test "detects added lines" do
      old = "line1\nline3"
      new = "line1\nline2\nline3"

      diff = Differ.diff_text(old, new)

      assert {:ins, "line2"} in diff
    end

    test "detects removed lines" do
      old = "line1\nline2\nline3"
      new = "line1\nline3"

      diff = Differ.diff_text(old, new)

      assert {:del, "line2"} in diff
    end

    test "detects modified lines" do
      old = "line1\nold line\nline3"
      new = "line1\nnew line\nline3"

      diff = Differ.diff_text(old, new)

      assert {:del, "old line"} in diff
      assert {:ins, "new line"} in diff
    end

    test "handles empty old text" do
      diff = Differ.diff_text("", "new line")

      assert {:ins, "new line"} in diff
    end

    test "handles empty new text" do
      diff = Differ.diff_text("old line", "")

      assert {:del, "old line"} in diff
    end
  end

  describe "has_changes?/1" do
    test "returns false for identical content" do
      diff = Differ.diff_text("same", "same")
      refute Differ.has_changes?(diff)
    end

    test "returns true when there are insertions" do
      diff = Differ.diff_text("old", "old\nnew")
      assert Differ.has_changes?(diff)
    end

    test "returns true when there are deletions" do
      diff = Differ.diff_text("old\nremove", "old")
      assert Differ.has_changes?(diff)
    end
  end

  describe "count_changes/1" do
    test "returns zero counts for identical content" do
      diff = Differ.diff_text("same\ncontent", "same\ncontent")
      {ins, del} = Differ.count_changes(diff)

      assert ins == 0
      assert del == 0
    end

    test "counts insertions" do
      diff = Differ.diff_text("line1", "line1\nline2\nline3")
      {ins, del} = Differ.count_changes(diff)

      assert ins == 2
      assert del == 0
    end

    test "counts deletions" do
      diff = Differ.diff_text("line1\nline2\nline3", "line1")
      {ins, del} = Differ.count_changes(diff)

      assert ins == 0
      assert del == 2
    end

    test "counts both insertions and deletions" do
      diff = Differ.diff_text("a\nb\nc", "a\nx\nc")
      {ins, del} = Differ.count_changes(diff)

      assert ins == 1
      assert del == 1
    end
  end

  describe "format_unified/2" do
    test "formats diff in unified format with header" do
      old = "line1\nold\nline3"
      new = "line1\nnew\nline3"

      diff = Differ.diff_text(old, new)
      output = Differ.format_unified(diff)

      assert output =~ "---"
      assert output =~ "+++"
      assert output =~ "-old"
      assert output =~ "+new"
    end

    test "includes @@ hunk markers" do
      old = "a\nb"
      new = "a\nc"

      diff = Differ.diff_text(old, new)
      output = Differ.format_unified(diff)

      assert output =~ "@@"
    end

    test "uses custom file names" do
      diff = Differ.diff_text("old", "new")
      output = Differ.format_unified(diff, old_name: "before.txt", new_name: "after.txt")

      assert output =~ "before.txt"
      assert output =~ "after.txt"
    end
  end
end

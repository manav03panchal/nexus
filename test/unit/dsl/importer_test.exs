defmodule Nexus.DSL.ImporterTest do
  use ExUnit.Case, async: true

  alias Nexus.DSL.Importer

  @fixtures_dir Path.join([__DIR__, "..", "..", "fixtures", "imports"])

  setup do
    # Create temp fixtures directory
    File.mkdir_p!(@fixtures_dir)
    on_exit(fn -> File.rm_rf!(@fixtures_dir) end)
    :ok
  end

  describe "glob_pattern?/1" do
    test "returns true for patterns with *" do
      assert Importer.glob_pattern?("*.exs")
      assert Importer.glob_pattern?("tasks/*.exs")
      assert Importer.glob_pattern?("**/*.exs")
    end

    test "returns true for patterns with ?" do
      assert Importer.glob_pattern?("task?.exs")
    end

    test "returns true for patterns with brackets" do
      assert Importer.glob_pattern?("[abc].exs")
      assert Importer.glob_pattern?("{a,b}.exs")
    end

    test "returns false for plain paths" do
      refute Importer.glob_pattern?("tasks/build.exs")
      refute Importer.glob_pattern?("config.exs")
    end
  end

  describe "resolve_file/2" do
    test "resolves absolute path" do
      path = Path.join(@fixtures_dir, "test.exs")
      File.write!(path, "# test")

      assert {:ok, ^path, "# test"} = Importer.resolve_file(path, base_path: @fixtures_dir)
    end

    test "resolves relative path from base_path" do
      path = Path.join(@fixtures_dir, "relative.exs")
      File.write!(path, "# relative")

      assert {:ok, resolved, "# relative"} =
               Importer.resolve_file("relative.exs", base_path: @fixtures_dir)

      assert resolved == path
    end

    test "returns error for non-existent file" do
      assert {:error, _} = Importer.resolve_file("nonexistent.exs", base_path: @fixtures_dir)
    end
  end

  describe "resolve_glob/2" do
    test "matches files with glob pattern" do
      File.write!(Path.join(@fixtures_dir, "a.exs"), "# a")
      File.write!(Path.join(@fixtures_dir, "b.exs"), "# b")
      File.write!(Path.join(@fixtures_dir, "c.txt"), "# c")

      assert {:ok, files} = Importer.resolve_glob("*.exs", base_path: @fixtures_dir)
      paths = Enum.map(files, fn {path, _} -> Path.basename(path) end)

      assert "a.exs" in paths
      assert "b.exs" in paths
      refute "c.txt" in paths
    end

    test "returns files sorted alphabetically" do
      File.write!(Path.join(@fixtures_dir, "z.exs"), "# z")
      File.write!(Path.join(@fixtures_dir, "a.exs"), "# a")
      File.write!(Path.join(@fixtures_dir, "m.exs"), "# m")

      assert {:ok, files} = Importer.resolve_glob("*.exs", base_path: @fixtures_dir)
      basenames = Enum.map(files, fn {path, _} -> Path.basename(path) end)

      assert basenames == ["a.exs", "m.exs", "z.exs"]
    end

    test "returns empty list when no glob matches" do
      # Glob patterns return empty list, not error
      assert {:ok, []} = Importer.resolve_glob("*.nonexistent", base_path: @fixtures_dir)
    end

    test "returns error for non-glob pattern with no match" do
      assert {:error, _} = Importer.resolve_glob("specific.exs", base_path: @fixtures_dir)
    end
  end

  describe "check_circular_import/2" do
    test "allows first import of a file" do
      chain = MapSet.new()
      assert {:ok, updated} = Importer.check_circular_import("/path/to/file.exs", chain)
      assert MapSet.member?(updated, Path.expand("/path/to/file.exs"))
    end

    test "detects circular import" do
      path = "/path/to/file.exs"
      chain = MapSet.new([Path.expand(path)])
      assert {:error, msg} = Importer.check_circular_import(path, chain)
      assert msg =~ "circular import"
    end
  end

  describe "base_dir/1" do
    test "returns directory of file path" do
      assert Importer.base_dir("/home/user/project/config.exs") == "/home/user/project"
    end

    test "handles nested paths" do
      assert Importer.base_dir("/a/b/c/d/file.exs") == "/a/b/c/d"
    end
  end
end

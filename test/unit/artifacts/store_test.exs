defmodule Nexus.Artifacts.StoreTest do
  use ExUnit.Case, async: false

  alias Nexus.Artifacts.Store

  setup do
    {:ok, pipeline_id} = Store.init()

    on_exit(fn ->
      Store.cleanup(pipeline_id)
    end)

    {:ok, pipeline_id: pipeline_id}
  end

  describe "init/0" do
    test "returns a pipeline ID" do
      {:ok, pipeline_id} = Store.init()

      assert is_binary(pipeline_id)
      assert String.length(pipeline_id) > 0

      Store.cleanup(pipeline_id)
    end

    test "generates unique IDs for each call" do
      {:ok, id1} = Store.init()
      {:ok, id2} = Store.init()

      assert id1 != id2

      Store.cleanup(id1)
      Store.cleanup(id2)
    end
  end

  describe "store/3 and fetch/2" do
    test "stores and retrieves artifact data", %{pipeline_id: pipeline_id} do
      content = "artifact content here"

      assert :ok = Store.store(pipeline_id, "my-artifact", content)
      assert {:ok, ^content} = Store.fetch(pipeline_id, "my-artifact")
    end

    test "stores binary data", %{pipeline_id: pipeline_id} do
      content = <<1, 2, 3, 4, 5>>

      assert :ok = Store.store(pipeline_id, "binary-artifact", content)
      assert {:ok, ^content} = Store.fetch(pipeline_id, "binary-artifact")
    end

    test "returns error for non-existent artifact", %{pipeline_id: pipeline_id} do
      assert {:error, {:not_found, "nonexistent"}} = Store.fetch(pipeline_id, "nonexistent")
    end

    test "overwrites existing artifact", %{pipeline_id: pipeline_id} do
      Store.store(pipeline_id, "artifact", "version1")
      Store.store(pipeline_id, "artifact", "version2")

      assert {:ok, "version2"} = Store.fetch(pipeline_id, "artifact")
    end
  end

  describe "exists?/2" do
    test "returns true for existing artifact", %{pipeline_id: pipeline_id} do
      Store.store(pipeline_id, "artifact", "content")

      assert Store.exists?(pipeline_id, "artifact")
    end

    test "returns false for non-existent artifact", %{pipeline_id: pipeline_id} do
      refute Store.exists?(pipeline_id, "nonexistent")
    end
  end

  describe "list/1" do
    test "lists all artifacts in a pipeline", %{pipeline_id: pipeline_id} do
      Store.store(pipeline_id, "artifact1", "content1")
      Store.store(pipeline_id, "artifact2", "content2")
      Store.store(pipeline_id, "artifact3", "content3")

      artifacts = Store.list(pipeline_id)

      assert length(artifacts) == 3
      assert "artifact1" in artifacts
      assert "artifact2" in artifacts
      assert "artifact3" in artifacts
    end

    test "returns empty list for pipeline with no artifacts", %{pipeline_id: pipeline_id} do
      assert Store.list(pipeline_id) == []
    end

    test "returns empty list for non-existent pipeline" do
      assert Store.list("fake-pipeline-id") == []
    end
  end

  describe "get_path/2" do
    test "returns the filesystem path for an artifact", %{pipeline_id: pipeline_id} do
      path = Store.get_path(pipeline_id, "my-artifact")

      assert is_binary(path)
      assert path =~ pipeline_id
      assert path =~ "my-artifact"
    end
  end

  describe "cleanup/1" do
    test "removes pipeline artifacts" do
      {:ok, pipeline_id} = Store.init()

      Store.store(pipeline_id, "artifact1", "content1")
      Store.store(pipeline_id, "artifact2", "content2")

      assert :ok = Store.cleanup(pipeline_id)

      # Artifacts should no longer exist
      assert Store.list(pipeline_id) == []
    end
  end

  describe "store_file/3" do
    test "copies file to artifact store", %{pipeline_id: pipeline_id} do
      # Create a temp file
      temp_path = Path.join(System.tmp_dir!(), "test_artifact_#{:rand.uniform(10000)}")
      File.write!(temp_path, "file content")

      on_exit(fn -> File.rm(temp_path) end)

      assert :ok = Store.store_file(pipeline_id, "copied-artifact", temp_path)
      assert {:ok, "file content"} = Store.fetch(pipeline_id, "copied-artifact")
    end
  end
end

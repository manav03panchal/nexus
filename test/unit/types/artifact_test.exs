defmodule Nexus.Types.ArtifactTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.Artifact

  describe "new/2" do
    test "creates artifact with path" do
      artifact = Artifact.new("build/output.tar.gz")

      assert artifact.path == "build/output.tar.gz"
    end

    test "uses nil as default for :as option" do
      artifact = Artifact.new("build/output.tar.gz")

      assert artifact.as == nil
    end

    test "producer_task is always nil from new/2" do
      artifact = Artifact.new("build/output.tar.gz")

      assert artifact.producer_task == nil
    end

    test "accepts :as option for alias" do
      artifact = Artifact.new("build/output.tar.gz", as: "release.tar.gz")

      assert artifact.as == "release.tar.gz"
    end
  end

  describe "name/1" do
    test "returns :as value when set" do
      artifact = Artifact.new("build/output.tar.gz", as: "release")

      assert Artifact.name(artifact) == "release"
    end

    test "returns path basename when :as is nil" do
      artifact = Artifact.new("build/output.tar.gz")

      assert Artifact.name(artifact) == "output.tar.gz"
    end

    test "handles paths without directory" do
      artifact = Artifact.new("artifact.txt")

      assert Artifact.name(artifact) == "artifact.txt"
    end
  end

  describe "struct" do
    test "enforces path key" do
      assert_raise ArgumentError, fn ->
        struct!(Artifact, as: "alias")
      end
    end

    test "can set producer_task directly on struct" do
      artifact = %Artifact{path: "test.txt", producer_task: :build}

      assert artifact.producer_task == :build
    end
  end
end

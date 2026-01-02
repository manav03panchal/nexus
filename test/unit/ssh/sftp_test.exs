defmodule Nexus.SSH.SFTPTest do
  use ExUnit.Case, async: true

  alias Nexus.SSH.SFTP

  # Note: Full SFTP integration tests require a real SSH server
  # These tests verify the module compiles and has the expected API

  describe "module API" do
    setup do
      # Ensure module is loaded
      {:module, _} = Code.ensure_loaded(SFTP)
      :ok
    end

    test "exports expected functions" do
      functions = SFTP.__info__(:functions)

      assert {:upload, 3} in functions
      assert {:upload, 4} in functions
      assert {:download, 3} in functions
      assert {:download, 4} in functions
      assert {:list_dir, 2} in functions
      assert {:stat, 2} in functions
      assert {:exists?, 2} in functions
      assert {:mkdir_p, 2} in functions
      assert {:rm, 2} in functions
    end
  end

  describe "upload/4 with missing local file" do
    test "returns error for non-existent local file" do
      # Create a mock connection struct (won't be used since file doesn't exist)
      fake_conn = %{ssh_connection: nil}

      result = SFTP.upload(fake_conn, "/nonexistent/file.txt", "/remote/file.txt")

      assert {:error, {:local_file_error, :enoent}} = result
    end
  end
end

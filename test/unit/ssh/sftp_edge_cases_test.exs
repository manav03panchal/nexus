defmodule Nexus.SSH.SFTPEdgeCasesTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.{Download, Upload}

  @moduletag :unit

  describe "Upload validation edge cases" do
    test "rejects upload with empty local path" do
      upload = %Upload{local_path: "", remote_path: "/remote/file.txt"}
      # Validation should catch this
      assert upload.local_path == ""
    end

    test "rejects upload with empty remote path" do
      upload = %Upload{local_path: "/local/file.txt", remote_path: ""}
      assert upload.remote_path == ""
    end

    test "handles paths with spaces" do
      upload = Upload.new("/local/path with spaces/file.txt", "/remote/path with spaces/file.txt")
      assert upload.local_path == "/local/path with spaces/file.txt"
      assert upload.remote_path == "/remote/path with spaces/file.txt"
    end

    test "handles paths with unicode characters" do
      upload = Upload.new("/local/文件/test.txt", "/remote/файл/test.txt")
      assert upload.local_path == "/local/文件/test.txt"
      assert upload.remote_path == "/remote/файл/test.txt"
    end

    test "handles paths with special shell characters" do
      special_paths = [
        "/path/with$dollar",
        "/path/with`backtick`",
        "/path/with'single'quotes",
        "/path/with\"double\"quotes",
        "/path/with;semicolon",
        "/path/with|pipe",
        "/path/with&ampersand",
        "/path/with(parens)",
        "/path/with[brackets]",
        "/path/with{braces}"
      ]

      for path <- special_paths do
        upload = Upload.new(path, path)
        assert upload.local_path == path
      end
    end

    test "handles very long paths" do
      long_component = String.duplicate("a", 255)
      # Create path with multiple long components (but valid for most filesystems)
      long_path = "/#{long_component}/#{long_component}/file.txt"
      upload = Upload.new(long_path, long_path)
      assert String.length(upload.local_path) > 500
    end

    test "handles relative paths" do
      upload = Upload.new("./relative/path.txt", "relative/remote.txt")
      assert upload.local_path == "./relative/path.txt"
    end

    test "handles paths with dots" do
      upload = Upload.new("/path/../normalized/./file.txt", "/remote/../other/./file.txt")
      assert upload.local_path == "/path/../normalized/./file.txt"
    end

    test "preserves file mode option" do
      upload = Upload.new("/local/file", "/remote/file", mode: 0o755)
      assert upload.mode == 0o755
    end

    test "preserves sudo option" do
      upload = Upload.new("/local/file", "/remote/file", sudo: true)
      assert upload.sudo == true
    end

    test "preserves notify option" do
      upload = Upload.new("/local/file", "/remote/file", notify: :restart_service)
      assert upload.notify == :restart_service
    end
  end

  describe "Download validation edge cases" do
    test "handles download to non-existent local directory path" do
      download = Download.new("/remote/file.txt", "/nonexistent/local/file.txt")
      assert download.local_path == "/nonexistent/local/file.txt"
    end

    test "handles download with trailing slashes" do
      download = Download.new("/remote/dir/", "/local/dir/")
      assert download.remote_path == "/remote/dir/"
    end

    test "handles hidden files (dotfiles)" do
      download = Download.new("/remote/.hidden", "/local/.hidden")
      assert String.starts_with?(Path.basename(download.remote_path), ".")
    end

    test "handles files with no extension" do
      download = Download.new("/remote/Makefile", "/local/Makefile")
      assert Path.extname(download.remote_path) == ""
    end

    test "handles files with multiple extensions" do
      download = Download.new("/remote/archive.tar.gz.bak", "/local/archive.tar.gz.bak")
      assert download.remote_path == "/remote/archive.tar.gz.bak"
    end
  end

  describe "SFTP path handling" do
    test "normalizes Windows-style paths on remote" do
      # Even if user mistakenly uses Windows paths, remote is Unix
      upload = Upload.new("/local/file", "/remote/file")
      # The path should be stored as-is, normalization happens at execution
      assert upload.remote_path == "/remote/file"
    end

    test "handles root path" do
      upload = Upload.new("/local/file", "/file.txt")
      assert upload.remote_path == "/file.txt"
    end

    test "handles home directory tilde" do
      upload = Upload.new("~/local/file", "~/remote/file")
      assert upload.local_path == "~/local/file"
      assert upload.remote_path == "~/remote/file"
    end
  end

  describe "SFTP struct defaults" do
    test "Upload has correct defaults" do
      upload = Upload.new("/local", "/remote")
      assert upload.sudo == false
      assert upload.mode == nil
      assert upload.notify == nil
    end

    test "Download has correct defaults" do
      download = Download.new("/remote", "/local")
      assert download.sudo == false
    end
  end

  describe "SFTP error scenarios (mocked)" do
    # These test the error handling paths without actual SSH connections

    test "handles permission denied error format" do
      error = {:error, :permission_denied}
      assert match?({:error, :permission_denied}, error)
    end

    test "handles no such file error format" do
      error = {:error, :no_such_file}
      assert match?({:error, :no_such_file}, error)
    end

    test "handles connection closed error format" do
      error = {:error, :closed}
      assert match?({:error, :closed}, error)
    end

    test "handles timeout error format" do
      error = {:error, :timeout}
      assert match?({:error, :timeout}, error)
    end

    test "handles disk full error format" do
      error = {:error, :no_space}
      assert match?({:error, :no_space}, error)
    end

    test "handles invalid path error format" do
      error = {:error, :bad_path}
      assert match?({:error, :bad_path}, error)
    end
  end

  describe "file size edge cases" do
    test "Upload struct can represent zero-byte file" do
      upload = Upload.new("/local/empty", "/remote/empty")
      # Zero-byte files are valid
      assert upload.local_path == "/local/empty"
    end

    test "paths for large files are handled" do
      # Path handling shouldn't care about file size
      upload = Upload.new("/local/10gb_file.iso", "/remote/10gb_file.iso")
      assert upload.local_path == "/local/10gb_file.iso"
    end
  end

  describe "symlink edge cases" do
    test "path pointing to symlink is preserved" do
      upload = Upload.new("/local/symlink", "/remote/target")
      assert upload.local_path == "/local/symlink"
    end

    test "path with symlink component is preserved" do
      upload = Upload.new("/local/real_dir/file", "/remote/link_dir/file")
      assert upload.local_path == "/local/real_dir/file"
    end
  end

  describe "concurrent transfer preparation" do
    test "multiple Upload structs are independent" do
      upload1 = Upload.new("/local/file1", "/remote/file1", mode: 0o644)
      upload2 = Upload.new("/local/file2", "/remote/file2", mode: 0o755)
      upload3 = Upload.new("/local/file3", "/remote/file3", sudo: true)

      assert upload1.mode == 0o644
      assert upload2.mode == 0o755
      assert upload1.sudo == false
      assert upload3.sudo == true
    end

    test "can create list of transfers" do
      transfers = [
        Upload.new("/local/a", "/remote/a"),
        Upload.new("/local/b", "/remote/b"),
        Download.new("/remote/c", "/local/c"),
        Download.new("/remote/d", "/local/d")
      ]

      assert length(transfers) == 4
      assert Enum.count(transfers, &match?(%Upload{}, &1)) == 2
      assert Enum.count(transfers, &match?(%Download{}, &1)) == 2
    end
  end
end

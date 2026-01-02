defmodule Nexus.Types.UploadTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.Upload

  describe "new/3" do
    test "creates upload with required fields" do
      upload = Upload.new("local/file.txt", "/remote/file.txt")

      assert upload.local_path == "local/file.txt"
      assert upload.remote_path == "/remote/file.txt"
      assert upload.sudo == false
      assert upload.mode == nil
      assert upload.notify == nil
    end

    test "creates upload with sudo option" do
      upload = Upload.new("config.txt", "/etc/app/config.txt", sudo: true)

      assert upload.sudo == true
    end

    test "creates upload with mode option" do
      upload = Upload.new("script.sh", "/opt/app/script.sh", mode: 0o755)

      assert upload.mode == 0o755
    end

    test "creates upload with notify option" do
      upload = Upload.new("nginx.conf", "/etc/nginx/nginx.conf", notify: :restart_nginx)

      assert upload.notify == :restart_nginx
    end

    test "creates upload with all options" do
      upload =
        Upload.new("config.txt", "/etc/app/config.txt",
          sudo: true,
          mode: 0o644,
          notify: :reload_config
        )

      assert upload.local_path == "config.txt"
      assert upload.remote_path == "/etc/app/config.txt"
      assert upload.sudo == true
      assert upload.mode == 0o644
      assert upload.notify == :reload_config
    end
  end

  describe "struct" do
    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Upload, [])
      end
    end
  end
end

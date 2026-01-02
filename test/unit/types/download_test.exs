defmodule Nexus.Types.DownloadTest do
  use ExUnit.Case, async: true

  alias Nexus.Types.Download

  describe "new/3" do
    test "creates download with required fields" do
      download = Download.new("/var/log/app.log", "logs/app.log")

      assert download.remote_path == "/var/log/app.log"
      assert download.local_path == "logs/app.log"
      assert download.sudo == false
    end

    test "creates download with sudo option" do
      download = Download.new("/etc/shadow", "shadow.bak", sudo: true)

      assert download.sudo == true
    end
  end

  describe "struct" do
    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Download, [])
      end
    end
  end
end

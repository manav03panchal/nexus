defmodule Nexus.Property.SFTPPropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Nexus.Types.{Download, Upload}

  @moduletag :property

  describe "Upload struct properties" do
    property "preserves local_path for any valid string" do
      check all(local_path <- string(:printable, min_length: 1)) do
        upload = Upload.new(local_path, "/remote/path")
        assert upload.local_path == local_path
      end
    end

    property "preserves remote_path for any valid string" do
      check all(remote_path <- string(:printable, min_length: 1)) do
        upload = Upload.new("/local/path", remote_path)
        assert upload.remote_path == remote_path
      end
    end

    property "sudo option is always boolean" do
      check all(
              local <- string(:printable, min_length: 1),
              remote <- string(:printable, min_length: 1),
              sudo <- boolean()
            ) do
        upload = Upload.new(local, remote, sudo: sudo)
        assert is_boolean(upload.sudo)
        assert upload.sudo == sudo
      end
    end

    property "mode option preserves integer values" do
      check all(
              local <- string(:printable, min_length: 1),
              remote <- string(:printable, min_length: 1),
              mode <- integer(0..0o777)
            ) do
        upload = Upload.new(local, remote, mode: mode)
        assert upload.mode == mode
      end
    end

    property "notify option preserves atom values" do
      check all(
              local <- string(:printable, min_length: 1),
              remote <- string(:printable, min_length: 1),
              handler_name <- atom(:alphanumeric)
            ) do
        upload = Upload.new(local, remote, notify: handler_name)
        assert upload.notify == handler_name
      end
    end
  end

  describe "Download struct properties" do
    property "preserves remote_path for any valid string" do
      check all(remote_path <- string(:printable, min_length: 1)) do
        download = Download.new(remote_path, "/local/path")
        assert download.remote_path == remote_path
      end
    end

    property "preserves local_path for any valid string" do
      check all(local_path <- string(:printable, min_length: 1)) do
        download = Download.new("/remote/path", local_path)
        assert download.local_path == local_path
      end
    end

    property "sudo option is always boolean" do
      check all(
              remote <- string(:printable, min_length: 1),
              local <- string(:printable, min_length: 1),
              sudo <- boolean()
            ) do
        download = Download.new(remote, local, sudo: sudo)
        assert is_boolean(download.sudo)
        assert download.sudo == sudo
      end
    end
  end

  describe "path handling properties" do
    property "paths with unicode are preserved" do
      check all(
              unicode_str <-
                string(:utf8, min_length: 1, max_length: 100)
                |> filter(&String.valid?/1)
            ) do
        local = "/local/#{unicode_str}/file"
        remote = "/remote/#{unicode_str}/file"
        upload = Upload.new(local, remote)
        assert upload.local_path == local
        assert upload.remote_path == remote
      end
    end

    property "paths with various separators are preserved" do
      check all(
              segments <-
                list_of(string(:alphanumeric, min_length: 1), min_length: 1, max_length: 5)
            ) do
        path = "/" <> Enum.join(segments, "/")
        upload = Upload.new(path, path)
        assert upload.local_path == path
      end
    end
  end
end

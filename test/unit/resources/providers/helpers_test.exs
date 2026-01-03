defmodule Nexus.Resources.Providers.HelpersTest do
  use ExUnit.Case, async: true

  alias Nexus.Resources.Providers.Helpers

  describe "escape_single/1" do
    test "wraps string in single quotes" do
      assert Helpers.escape_single("hello") == "'hello'"
    end

    test "escapes embedded single quotes" do
      result = Helpers.escape_single("it's")
      assert result =~ "it"
      assert result =~ "s"
    end

    test "handles empty string" do
      assert Helpers.escape_single("") == "''"
    end

    test "handles string with spaces" do
      assert Helpers.escape_single("hello world") == "'hello world'"
    end
  end

  describe "escape_name/1" do
    test "allows alphanumeric characters" do
      assert Helpers.escape_name("nginx123") == "nginx123"
    end

    test "allows dots" do
      assert Helpers.escape_name("php8.1") == "php8.1"
    end

    test "allows underscores" do
      assert Helpers.escape_name("my_package") == "my_package"
    end

    test "allows plus and minus" do
      assert Helpers.escape_name("g++-10") == "g++-10"
    end

    test "removes shell metacharacters" do
      result = Helpers.escape_name("bad;rm -rf /")
      refute result =~ ";"
    end

    test "handles empty string" do
      assert Helpers.escape_name("") == ""
    end
  end

  describe "escape_path/1" do
    test "allows forward slashes" do
      assert Helpers.escape_path("/usr/local/bin") == "/usr/local/bin"
    end

    test "allows alphanumeric characters" do
      assert Helpers.escape_path("/var/log123") == "/var/log123"
    end

    test "allows dots in path" do
      assert Helpers.escape_path("/etc/nginx/nginx.conf") == "/etc/nginx/nginx.conf"
    end

    test "allows underscores" do
      assert Helpers.escape_path("/var/my_app/logs") == "/var/my_app/logs"
    end

    test "allows hyphens" do
      assert Helpers.escape_path("/opt/my-app") == "/opt/my-app"
    end

    test "handles empty string" do
      assert Helpers.escape_path("") == ""
    end
  end

  describe "validate_absolute_path/1" do
    test "returns :ok for absolute path starting with /" do
      assert Helpers.validate_absolute_path("/etc/nginx") == :ok
    end

    test "returns :ok for root path" do
      assert Helpers.validate_absolute_path("/") == :ok
    end

    test "returns error for relative path" do
      assert {:error, msg} = Helpers.validate_absolute_path("relative/path")
      assert msg =~ "absolute"
    end

    test "returns error for path starting with dot" do
      assert {:error, msg} = Helpers.validate_absolute_path("./current")
      assert msg =~ "absolute"
    end

    test "returns error for empty path" do
      assert {:error, _} = Helpers.validate_absolute_path("")
    end
  end

  describe "validate_mode/1" do
    test "returns :ok for nil" do
      assert Helpers.validate_mode(nil) == :ok
    end

    test "returns :ok for valid mode 0o644" do
      assert Helpers.validate_mode(0o644) == :ok
    end

    test "returns :ok for valid mode 0o755" do
      assert Helpers.validate_mode(0o755) == :ok
    end

    test "returns :ok for minimum valid mode 0" do
      assert Helpers.validate_mode(0) == :ok
    end

    test "returns :ok for maximum valid mode 0o7777" do
      assert Helpers.validate_mode(0o7777) == :ok
    end

    test "returns error for mode greater than 0o7777" do
      assert {:error, msg} = Helpers.validate_mode(0o10000)
      assert msg =~ "invalid mode"
    end

    test "returns error for negative mode" do
      assert {:error, msg} = Helpers.validate_mode(-1)
      assert msg =~ "invalid mode"
    end
  end

  describe "format_mode/1" do
    test "formats 0o644 as octal string" do
      assert Helpers.format_mode(0o644) == "644"
    end

    test "formats 0o755 as octal string" do
      assert Helpers.format_mode(0o755) == "755"
    end

    test "formats 0o400 as octal string" do
      assert Helpers.format_mode(0o400) == "400"
    end

    test "formats 0o7777 as octal string" do
      assert Helpers.format_mode(0o7777) == "7777"
    end

    test "formats 0 as octal string" do
      assert Helpers.format_mode(0) == "0"
    end
  end

  describe "parse_exit_code/1" do
    test "extracts exit code from success tuple" do
      assert Helpers.parse_exit_code({:ok, "output", 0}) == {:ok, 0}
    end

    test "extracts exit code from non-zero exit" do
      assert Helpers.parse_exit_code({:ok, "error output", 127}) == {:ok, 127}
    end

    test "passes through error tuple" do
      assert Helpers.parse_exit_code({:error, :timeout}) == {:error, :timeout}
    end
  end

  describe "command_succeeded?/1" do
    test "returns true for exit code 0" do
      assert Helpers.command_succeeded?({:ok, "output", 0}) == true
    end

    test "returns false for non-zero exit code" do
      assert Helpers.command_succeeded?({:ok, "error", 1}) == false
    end

    test "returns false for exit code 127" do
      assert Helpers.command_succeeded?({:ok, "command not found", 127}) == false
    end

    test "returns false for error tuple" do
      assert Helpers.command_succeeded?({:error, :timeout}) == false
    end
  end

  describe "join_names/1" do
    test "joins list of names with spaces" do
      assert Helpers.join_names(["nginx", "curl", "vim"]) == "nginx curl vim"
    end

    test "handles single item list" do
      assert Helpers.join_names(["nginx"]) == "nginx"
    end

    test "handles empty list" do
      assert Helpers.join_names([]) == ""
    end
  end
end

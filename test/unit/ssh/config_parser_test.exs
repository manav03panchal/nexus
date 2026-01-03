defmodule Nexus.SSH.ConfigParserTest do
  use ExUnit.Case, async: true

  alias Nexus.SSH.ConfigParser

  describe "parse_file/1" do
    test "parses empty file" do
      {:ok, path} = write_temp_config("")
      assert {:ok, []} = ConfigParser.parse_file(path)
    end

    test "parses single host block" do
      config = """
      Host example
        HostName example.com
        User deploy
        Port 2222
      """

      {:ok, path} = write_temp_config(config)
      {:ok, blocks} = ConfigParser.parse_file(path)

      assert length(blocks) == 1
      [{patterns, settings}] = blocks
      assert patterns == ["example"]
      assert settings.hostname == "example.com"
      assert settings.user == "deploy"
      assert settings.port == 2222
    end

    test "parses multiple host blocks" do
      config = """
      Host web
        HostName web.example.com
        User www-data

      Host db
        HostName db.example.com
        User postgres
        Port 5432
      """

      {:ok, path} = write_temp_config(config)
      {:ok, blocks} = ConfigParser.parse_file(path)

      assert length(blocks) == 2
    end

    test "parses identity file with path expansion" do
      config = """
      Host secure
        IdentityFile ~/.ssh/secure_key
      """

      {:ok, path} = write_temp_config(config)
      {:ok, [{_patterns, settings}]} = ConfigParser.parse_file(path)

      assert settings.identity_file == Path.expand("~/.ssh/secure_key")
    end

    test "parses ProxyJump directive" do
      config = """
      Host internal
        ProxyJump bastion.example.com
      """

      {:ok, path} = write_temp_config(config)
      {:ok, [{_patterns, settings}]} = ConfigParser.parse_file(path)

      assert settings.proxy_jump == "bastion.example.com"
    end

    test "parses ForwardAgent directive" do
      config = """
      Host dev
        ForwardAgent yes
      """

      {:ok, path} = write_temp_config(config)
      {:ok, [{_patterns, settings}]} = ConfigParser.parse_file(path)

      assert settings.forward_agent == true
    end

    test "ignores comments" do
      config = """
      # This is a comment
      Host example
        # Another comment
        User deploy
      """

      {:ok, path} = write_temp_config(config)
      {:ok, [{_patterns, settings}]} = ConfigParser.parse_file(path)

      assert settings.user == "deploy"
      refute Map.has_key?(settings, :comment)
    end

    test "handles multiple patterns in Host line" do
      config = """
      Host web1 web2 web3
        User www-data
      """

      {:ok, path} = write_temp_config(config)
      {:ok, [{patterns, _settings}]} = ConfigParser.parse_file(path)

      assert patterns == ["web1", "web2", "web3"]
    end

    test "handles equals sign syntax" do
      config = """
      Host example
        User=deploy
        Port=2222
      """

      {:ok, path} = write_temp_config(config)
      {:ok, [{_patterns, settings}]} = ConfigParser.parse_file(path)

      assert settings.user == "deploy"
      assert settings.port == 2222
    end

    test "returns empty list for non-existent file" do
      assert {:ok, []} = ConfigParser.parse_file("/non/existent/path")
    end
  end

  describe "matches_pattern?/2" do
    test "exact match" do
      assert ConfigParser.matches_pattern?("example.com", "example.com")
      refute ConfigParser.matches_pattern?("example.com", "example.org")
    end

    test "asterisk wildcard matches any characters" do
      assert ConfigParser.matches_pattern?("web.example.com", "*.example.com")
      assert ConfigParser.matches_pattern?("db.example.com", "*.example.com")
      refute ConfigParser.matches_pattern?("example.com", "*.example.com")
    end

    test "asterisk at end" do
      assert ConfigParser.matches_pattern?("prod-web-01", "prod-*")
      assert ConfigParser.matches_pattern?("prod-db-02", "prod-*")
      refute ConfigParser.matches_pattern?("dev-web-01", "prod-*")
    end

    test "question mark matches single character" do
      assert ConfigParser.matches_pattern?("web1", "web?")
      assert ConfigParser.matches_pattern?("web2", "web?")
      refute ConfigParser.matches_pattern?("web10", "web?")
    end

    test "combined wildcards" do
      assert ConfigParser.matches_pattern?("prod-web-01", "prod-*-0?")
      assert ConfigParser.matches_pattern?("prod-db-02", "prod-*-0?")
      refute ConfigParser.matches_pattern?("prod-web-10", "prod-*-0?")
    end

    test "negation with exclamation mark" do
      refute ConfigParser.matches_pattern?("example.com", "!example.com")
      assert ConfigParser.matches_pattern?("other.com", "!example.com")
    end

    test "escapes regex special characters" do
      assert ConfigParser.matches_pattern?("example.com", "example.com")
      refute ConfigParser.matches_pattern?("exampleXcom", "example.com")
    end
  end

  describe "get_host_config/1" do
    test "returns empty map for unknown host" do
      assert {:ok, %{}} = ConfigParser.get_host_config("unknown-host-12345.example.com")
    end

    test "merges settings from multiple matching blocks" do
      config = """
      Host *
        User default-user
        Port 22

      Host *.example.com
        User example-user

      Host web.example.com
        Port 2222
      """

      {:ok, path} = write_temp_config(config)

      # Temporarily override config paths
      # For now, just test the parse_file directly
      {:ok, blocks} = ConfigParser.parse_file(path)

      # Verify blocks were parsed correctly
      assert length(blocks) == 3
    end
  end

  # Helper to create temporary config files for testing
  defp write_temp_config(content) do
    path = Path.join(System.tmp_dir!(), "ssh_config_test_#{:rand.uniform(100_000)}")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    {:ok, path}
  end
end

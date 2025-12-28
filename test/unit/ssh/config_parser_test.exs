defmodule Nexus.SSH.ConfigParserTest do
  use ExUnit.Case, async: true

  alias Nexus.SSH.ConfigParser

  @moduletag :unit

  describe "parse_string/1" do
    test "parses basic host configuration" do
      config = """
      Host myserver
        HostName example.com
        User deploy
        Port 2222
      """

      [%{pattern: "myserver", config: parsed}] = ConfigParser.parse_string(config)

      assert parsed.hostname == "example.com"
      assert parsed.user == "deploy"
      assert parsed.port == 2222
    end

    test "parses multiple host blocks" do
      config = """
      Host web
        HostName web.example.com
        User admin

      Host db
        HostName db.example.com
        Port 2222
      """

      configs = ConfigParser.parse_string(config)
      assert length(configs) == 2

      web = Enum.find(configs, &(&1.pattern == "web"))
      db = Enum.find(configs, &(&1.pattern == "db"))

      assert web.config.hostname == "web.example.com"
      assert web.config.user == "admin"
      assert db.config.hostname == "db.example.com"
      assert db.config.port == 2222
    end

    test "parses wildcard host patterns" do
      config = """
      Host *
        User defaultuser
        Port 22

      Host prod-*
        User produser
        IdentityFile ~/.ssh/prod_key
      """

      configs = ConfigParser.parse_string(config)
      assert length(configs) == 2

      wildcard = Enum.find(configs, &(&1.pattern == "*"))
      prod = Enum.find(configs, &(&1.pattern == "prod-*"))

      assert wildcard.config.user == "defaultuser"
      assert prod.config.user == "produser"
    end

    test "parses identity file with tilde expansion" do
      config = """
      Host server
        IdentityFile ~/.ssh/my_key
      """

      [%{config: parsed}] = ConfigParser.parse_string(config)

      assert parsed.identity_file == Path.expand("~/.ssh/my_key")
    end

    test "parses connect timeout" do
      config = """
      Host slow
        ConnectTimeout 30
      """

      [%{config: parsed}] = ConfigParser.parse_string(config)
      assert parsed.connect_timeout == 30
    end

    test "parses forward agent" do
      config = """
      Host forwarding
        ForwardAgent yes
      """

      [%{config: parsed}] = ConfigParser.parse_string(config)
      assert parsed.forward_agent == true
    end

    test "parses strict host key checking" do
      config = """
      Host insecure
        StrictHostKeyChecking no
      """

      [%{config: parsed}] = ConfigParser.parse_string(config)
      assert parsed.strict_host_key_checking == :no
    end

    test "parses proxy jump" do
      config = """
      Host target
        ProxyJump bastion.example.com
      """

      [%{config: parsed}] = ConfigParser.parse_string(config)
      assert parsed.proxy_jump == "bastion.example.com"
    end

    test "ignores comments" do
      config = """
      # This is a comment
      Host server
        # Another comment
        HostName example.com
        # User comment
        User deploy
      """

      [%{config: parsed}] = ConfigParser.parse_string(config)
      assert parsed.hostname == "example.com"
      assert parsed.user == "deploy"
    end

    test "handles empty content" do
      configs = ConfigParser.parse_string("")
      assert configs == []
    end

    test "handles comments only" do
      config = """
      # Just a comment
      # Another comment
      """

      configs = ConfigParser.parse_string(config)
      assert configs == []
    end

    test "handles equals sign format" do
      config = """
      Host server
        HostName=example.com
        User=deploy
        Port=2222
      """

      [%{config: parsed}] = ConfigParser.parse_string(config)
      assert parsed.hostname == "example.com"
      assert parsed.user == "deploy"
      assert parsed.port == 2222
    end

    test "ignores unknown directives" do
      config = """
      Host server
        HostName example.com
        UnknownDirective value
        AnotherUnknown stuff
      """

      [%{config: parsed}] = ConfigParser.parse_string(config)
      assert parsed.hostname == "example.com"
      refute Map.has_key?(parsed, :unknown_directive)
    end

    test "handles invalid port gracefully" do
      config = """
      Host server
        HostName example.com
        Port invalid
      """

      [%{config: parsed}] = ConfigParser.parse_string(config)
      assert parsed.hostname == "example.com"
      refute Map.has_key?(parsed, :port)
    end
  end

  describe "lookup/2" do
    test "finds exact host match" do
      configs =
        ConfigParser.parse_string("""
        Host web
          HostName web.example.com
          User webuser
        """)

      result = ConfigParser.lookup("web", configs)

      assert result.hostname == "web.example.com"
      assert result.user == "webuser"
    end

    test "matches wildcard pattern" do
      configs =
        ConfigParser.parse_string("""
        Host prod-*
          User produser
          IdentityFile ~/.ssh/prod_key
        """)

      result = ConfigParser.lookup("prod-web", configs)

      assert result.user == "produser"
      assert result.hostname == "prod-web"
    end

    test "merges configurations from multiple matches" do
      configs =
        ConfigParser.parse_string("""
        Host *
          User defaultuser
          Port 22

        Host prod-*
          User produser

        Host prod-web
          HostName 10.0.1.5
        """)

      result = ConfigParser.lookup("prod-web", configs)

      # Our implementation merges with later matches taking precedence
      # So prod-web sets hostname, then prod-* would override user if not set,
      # but we use Map.merge(config, acc) so first-parsed values win
      assert result.hostname == "10.0.1.5"
      # defaultuser wins because * is parsed first and we merge INTO acc
      assert result.user == "defaultuser"
      assert result.port == 22
    end

    test "returns hostname when no match found" do
      configs =
        ConfigParser.parse_string("""
        Host other
          User otheruser
        """)

      result = ConfigParser.lookup("unmatched", configs)

      assert result.hostname == "unmatched"
      assert map_size(result) == 1
    end

    test "handles single character wildcard" do
      configs =
        ConfigParser.parse_string("""
        Host web?
          User webuser
        """)

      result = ConfigParser.lookup("web1", configs)
      assert result.user == "webuser"

      result2 = ConfigParser.lookup("web12", configs)
      refute Map.has_key?(result2, :user)
    end

    test "handles multiple patterns in host line" do
      configs =
        ConfigParser.parse_string("""
        Host web db cache
          User admin
        """)

      assert ConfigParser.lookup("web", configs).user == "admin"
      assert ConfigParser.lookup("db", configs).user == "admin"
      assert ConfigParser.lookup("cache", configs).user == "admin"
    end
  end

  describe "parse/1" do
    test "returns empty list for non-existent file" do
      {:ok, configs} = ConfigParser.parse("/nonexistent/path/config")
      assert configs == []
    end

    test "returns error for unreadable file" do
      # Create a temp directory (can't read as file)
      tmp_dir = System.tmp_dir!()

      {:error, {:config_read_error, _path, :eisdir}} =
        ConfigParser.parse(tmp_dir)
    end
  end

  describe "to_connect_opts/1" do
    test "converts basic config to connection options" do
      config = %{
        hostname: "example.com",
        user: "deploy",
        port: 2222
      }

      opts = ConfigParser.to_connect_opts(config)

      assert Keyword.get(opts, :user) == "deploy"
      assert Keyword.get(opts, :port) == 2222
    end

    test "converts identity file to identity option" do
      config = %{
        identity_file: "/path/to/key"
      }

      opts = ConfigParser.to_connect_opts(config)
      assert Keyword.get(opts, :identity) == "/path/to/key"
    end

    test "converts connect timeout to milliseconds" do
      config = %{
        connect_timeout: 30
      }

      opts = ConfigParser.to_connect_opts(config)
      assert Keyword.get(opts, :timeout) == 30_000
    end

    test "handles empty config" do
      opts = ConfigParser.to_connect_opts(%{})
      assert opts == []
    end
  end

  describe "default_path/0" do
    test "returns expanded SSH config path" do
      path = ConfigParser.default_path()
      assert String.ends_with?(path, ".ssh/config")
    end
  end
end

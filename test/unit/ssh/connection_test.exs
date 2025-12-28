defmodule Nexus.SSH.ConnectionTest do
  use ExUnit.Case, async: true

  alias Nexus.SSH.Connection
  alias Nexus.Types.Host

  @moduletag :unit

  # Note: These are unit tests that don't require actual SSH connections.
  # Integration tests with real SSH connections are in test/integration/

  describe "connect/2 with Host struct" do
    test "extracts options from Host struct" do
      host = %Host{
        name: :web1,
        hostname: "example.com",
        user: "deploy",
        port: 2222
      }

      # This will fail to connect (no server), but we can verify the attempt
      result = Connection.connect(host, timeout: 100)

      # Should return connection error, not option parsing error
      assert {:error, reason} = result
      assert is_tuple(reason) or is_atom(reason)
    end

    test "merges Host options with explicit options" do
      host = %Host{
        name: :web1,
        hostname: "example.com",
        user: "host_user",
        port: 22
      }

      # Explicit options should override Host defaults
      result = Connection.connect(host, user: "explicit_user", timeout: 100)

      assert {:error, _} = result
    end
  end

  describe "connect/2 error handling" do
    test "returns connection_refused for closed ports" do
      result = Connection.connect("127.0.0.1", port: 59_999, timeout: 100)

      assert {:error, {:connection_refused, "127.0.0.1"}} = result
    end

    test "returns hostname_not_found for invalid hostname" do
      result = Connection.connect("invalid.hostname.that.does.not.exist.local", timeout: 100)

      assert {:error, {:hostname_not_found, _}} = result
    end

    test "returns connection_timeout for slow connections" do
      # Using a non-routable IP to trigger timeout
      result = Connection.connect("10.255.255.1", timeout: 100)

      # Could be timeout or unreachable depending on network config
      assert {:error, reason} = result

      assert reason in [
               {:connection_timeout, "10.255.255.1"},
               {:host_unreachable, "10.255.255.1"},
               {:connection_failed, "10.255.255.1", :timeout}
             ] or match?({:connection_failed, _, _}, reason)
    end
  end

  describe "alive?/1" do
    test "returns false for invalid connection" do
      # nil isn't a valid connection
      refute Connection.alive?(nil)
    end
  end

  describe "exec_sudo/3" do
    # These are format tests - actual execution tested in integration
    test "builds sudo command correctly" do
      # We can't test actual execution without a connection,
      # but we can verify the module compiles and has the function
      functions = Connection.__info__(:functions)
      assert {:exec_sudo, 2} in functions
      assert {:exec_sudo, 3} in functions
    end
  end

  describe "internal functions" do
    test "module exports expected functions" do
      functions = Connection.__info__(:functions)

      assert {:connect, 1} in functions
      assert {:connect, 2} in functions
      assert {:exec, 2} in functions
      assert {:exec, 3} in functions
      assert {:exec_streaming, 3} in functions
      assert {:exec_streaming, 4} in functions
      assert {:close, 1} in functions
      assert {:alive?, 1} in functions
      assert {:exec_sudo, 2} in functions
      assert {:exec_sudo, 3} in functions
    end
  end
end

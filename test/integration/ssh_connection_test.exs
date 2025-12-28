defmodule Nexus.SSH.ConnectionIntegrationTest do
  use ExUnit.Case

  alias Nexus.SSH.Connection
  alias Nexus.Types.Host

  @moduletag :integration

  # These tests require Docker SSH containers to be running:
  # docker-compose -f docker-compose.test.yml up -d

  @password_host "127.0.0.1"
  @password_port 2232
  @password_user "testuser"
  @password "testpass"

  @key_host "127.0.0.1"
  @key_port 2233
  @key_user "testuser"

  # Use File.cwd! to get project root for reliable path resolution
  # Key must be named id_ed25519 for Erlang SSH to find it
  def key_file do
    Path.join([File.cwd!(), "test", "fixtures", "ssh_keys", "id_ed25519"])
  end

  describe "connect with password" do
    @tag :integration
    test "connects with password authentication" do
      {:ok, conn} =
        Connection.connect(@password_host,
          port: @password_port,
          user: @password_user,
          password: @password,
          silently_accept_hosts: true
        )

      assert conn != nil
      Connection.close(conn)
    end

    @tag :integration
    test "executes command and returns output" do
      {:ok, conn} =
        Connection.connect(@password_host,
          port: @password_port,
          user: @password_user,
          password: @password,
          silently_accept_hosts: true
        )

      {:ok, output, exit_code} = Connection.exec(conn, "echo hello")

      assert exit_code == 0
      assert String.trim(output) == "hello"

      Connection.close(conn)
    end

    @tag :integration
    test "returns correct exit code for failed commands" do
      {:ok, conn} =
        Connection.connect(@password_host,
          port: @password_port,
          user: @password_user,
          password: @password,
          silently_accept_hosts: true
        )

      {:ok, _output, exit_code} = Connection.exec(conn, "exit 42")

      assert exit_code == 42

      Connection.close(conn)
    end

    @tag :integration
    test "captures stderr output" do
      {:ok, conn} =
        Connection.connect(@password_host,
          port: @password_port,
          user: @password_user,
          password: @password,
          silently_accept_hosts: true
        )

      {:ok, output, _exit_code} = Connection.exec(conn, "echo error >&2")

      assert String.contains?(output, "error")

      Connection.close(conn)
    end

    @tag :integration
    test "alive? returns true for valid connection" do
      {:ok, conn} =
        Connection.connect(@password_host,
          port: @password_port,
          user: @password_user,
          password: @password,
          silently_accept_hosts: true
        )

      assert Connection.alive?(conn)

      Connection.close(conn)
    end

    @tag :integration
    test "executes with environment variables" do
      {:ok, conn} =
        Connection.connect(@password_host,
          port: @password_port,
          user: @password_user,
          password: @password,
          silently_accept_hosts: true
        )

      {:ok, output, 0} = Connection.exec(conn, "echo $MY_VAR", env: %{"MY_VAR" => "test_value"})

      assert String.trim(output) == "test_value"

      Connection.close(conn)
    end
  end

  describe "connect with key" do
    @tag :integration
    test "connects with key authentication" do
      {:ok, conn} =
        Connection.connect(@key_host,
          port: @key_port,
          user: @key_user,
          identity: key_file(),
          silently_accept_hosts: true
        )

      assert conn != nil
      Connection.close(conn)
    end

    @tag :integration
    test "executes command with key auth" do
      {:ok, conn} =
        Connection.connect(@key_host,
          port: @key_port,
          user: @key_user,
          identity: key_file(),
          silently_accept_hosts: true
        )

      {:ok, output, 0} = Connection.exec(conn, "whoami")

      assert String.trim(output) == @key_user

      Connection.close(conn)
    end
  end

  describe "connect with Host struct" do
    @tag :integration
    test "connects using Host struct" do
      host = %Host{
        name: :test_host,
        hostname: @password_host,
        user: @password_user,
        port: @password_port
      }

      {:ok, conn} =
        Connection.connect(host,
          password: @password,
          silently_accept_hosts: true
        )

      {:ok, output, 0} = Connection.exec(conn, "hostname")

      assert is_binary(output)
      Connection.close(conn)
    end
  end

  describe "streaming execution" do
    @tag :integration
    test "streams output via callback" do
      {:ok, conn} =
        Connection.connect(@password_host,
          port: @password_port,
          user: @password_user,
          password: @password,
          silently_accept_hosts: true
        )

      collected = :ets.new(:collected, [:set, :public])
      :ets.insert(collected, {:chunks, []})

      callback = fn chunk ->
        [{:chunks, chunks}] = :ets.lookup(collected, :chunks)
        :ets.insert(collected, {:chunks, [chunk | chunks]})
      end

      {:ok, exit_code} = Connection.exec_streaming(conn, "echo line1; echo line2", callback)

      assert exit_code == 0

      [{:chunks, chunks}] = :ets.lookup(collected, :chunks)
      :ets.delete(collected)

      # Verify we received stdout chunks
      stdout_chunks = Enum.filter(chunks, fn {type, _} -> type == :stdout end)
      assert stdout_chunks != []

      Connection.close(conn)
    end
  end

  describe "error handling" do
    @tag :integration
    test "returns auth error for wrong password" do
      result =
        Connection.connect(@password_host,
          port: @password_port,
          user: @password_user,
          password: "wrongpassword",
          silently_accept_hosts: true,
          timeout: 5_000
        )

      assert {:error, reason} = result
      assert is_tuple(reason)
    end

    @tag :integration
    test "returns error for wrong port" do
      result =
        Connection.connect(@password_host,
          port: 29_999,
          user: @password_user,
          password: @password,
          timeout: 1_000
        )

      assert {:error, {:connection_refused, _}} = result
    end
  end

  describe "concurrent connections" do
    @tag :integration
    test "handles multiple concurrent connections" do
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            {:ok, conn} =
              Connection.connect(@password_host,
                port: @password_port,
                user: @password_user,
                password: @password,
                silently_accept_hosts: true
              )

            {:ok, output, 0} = Connection.exec(conn, "echo #{i}")
            Connection.close(conn)
            String.trim(output)
          end)
        end

      results = Task.await_many(tasks, 30_000)

      assert length(results) == 5
      assert Enum.all?(results, &is_binary/1)
    end
  end
end

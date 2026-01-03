defmodule Nexus.SSH.ProxyTest do
  use ExUnit.Case, async: true

  alias Nexus.SSH.Proxy

  @moduletag :unit

  describe "module API" do
    test "Proxy module is loaded" do
      {:module, _} = Code.ensure_loaded(Proxy)
      assert Code.ensure_loaded?(Proxy)
    end

    test "Proxy exports expected functions" do
      functions = Proxy.__info__(:functions)

      assert {:connect_via_jump, 2} in functions
      assert {:connect_via_jump, 3} in functions
      assert {:connect_via_chain, 3} in functions
    end
  end

  describe "connect_via_jump/3" do
    test "returns error when jump host connection fails" do
      result =
        Proxy.connect_via_jump(
          "target.internal",
          "127.0.0.1",
          target_opts: [user: "app", timeout: 100],
          jump_opts: [user: "jump", port: 59_999, timeout: 100]
        )

      assert {:error, {:jump_connect_failed, "127.0.0.1", _reason}} = result
    end

    test "accepts empty options and uses defaults" do
      result =
        Proxy.connect_via_jump("target.internal", "127.0.0.1",
          jump_opts: [port: 59_999, timeout: 100]
        )

      assert {:error, _} = result
    end

    test "handles hostname lookup failure" do
      result =
        Proxy.connect_via_jump(
          "target.internal",
          "nonexistent.host.invalid.local",
          jump_opts: [timeout: 100]
        )

      assert {:error, {:jump_connect_failed, "nonexistent.host.invalid.local", _}} = result
    end
  end

  describe "connect_via_chain/3 with empty chain" do
    test "connects directly when chain is empty" do
      result = Proxy.connect_via_chain("127.0.0.1", [], target_opts: [port: 59_999, timeout: 100])

      assert {:error, reason} = result
      refute match?({:chain_failed, _, _}, reason)
    end
  end

  describe "connect_via_chain/3 with single jump" do
    test "uses connect_via_jump for single jump host" do
      result =
        Proxy.connect_via_chain(
          "target.internal",
          ["127.0.0.1"],
          target_opts: [timeout: 100],
          jump_opts: [port: 59_999, timeout: 100]
        )

      assert {:error, {:jump_connect_failed, "127.0.0.1", _}} = result
    end
  end

  describe "connect_via_chain/3 with multiple jumps" do
    test "returns chain_failed error when first jump fails" do
      result =
        Proxy.connect_via_chain(
          "target.internal",
          ["jump1.invalid.local", "jump2.invalid.local"],
          target_opts: [timeout: 100],
          jump_opts: [timeout: 100]
        )

      assert {:error, {:chain_failed, _hosts, _reason}} = result
    end

    test "includes jump host list in chain_failed error" do
      jump_hosts = ["jump1.invalid.local", "jump2.invalid.local"]

      {:error, {:chain_failed, returned_hosts, _reason}} =
        Proxy.connect_via_chain(
          "target.internal",
          jump_hosts,
          jump_opts: [timeout: 100]
        )

      assert returned_hosts == jump_hosts
    end
  end

  describe "proxy command building" do
    test "includes port option in proxy command" do
      result =
        Proxy.connect_via_jump(
          "target.internal",
          "127.0.0.1",
          target_opts: [port: 3022, timeout: 100],
          jump_opts: [port: 59_999, timeout: 100]
        )

      assert {:error, _} = result
    end

    test "handles identity file option" do
      tmp_dir = System.tmp_dir!()
      key_path = Path.join(tmp_dir, "test_proxy_key_#{:rand.uniform(10000)}")
      File.write!(key_path, "fake key content")

      on_exit(fn -> File.rm(key_path) end)

      result =
        Proxy.connect_via_jump(
          "target.internal",
          "127.0.0.1",
          target_opts: [identity: key_path, timeout: 100],
          jump_opts: [identity: key_path, port: 59_999, timeout: 100]
        )

      assert {:error, _} = result
    end

    test "handles user option" do
      result =
        Proxy.connect_via_jump(
          "target.internal",
          "127.0.0.1",
          target_opts: [user: "custom_user", timeout: 100],
          jump_opts: [user: "jump_user", port: 59_999, timeout: 100]
        )

      assert {:error, _} = result
    end
  end

  describe "maybe_add_identity behavior" do
    test "handles nil identity gracefully" do
      result =
        Proxy.connect_via_jump(
          "target.internal",
          "127.0.0.1",
          target_opts: [identity: nil, timeout: 100],
          jump_opts: [port: 59_999, timeout: 100]
        )

      assert {:error, _} = result
    end

    test "handles non-existent identity file" do
      result =
        Proxy.connect_via_jump(
          "target.internal",
          "127.0.0.1",
          target_opts: [identity: "/nonexistent/key", timeout: 100],
          jump_opts: [port: 59_999, timeout: 100]
        )

      assert {:error, _} = result
    end
  end
end

defmodule Nexus.Resources.ValidatorsTest do
  use ExUnit.Case, async: true

  alias Nexus.Resources.Validators

  describe "validate_path/1" do
    test "returns :ok for absolute path" do
      assert Validators.validate_path("/etc/nginx") == :ok
    end

    test "returns :ok for root path" do
      assert Validators.validate_path("/") == :ok
    end

    test "returns error for relative path" do
      assert {:error, msg} = Validators.validate_path("relative/path")
      assert msg =~ "absolute"
    end

    test "returns error for path starting with dot" do
      assert {:error, _} = Validators.validate_path("./current")
    end

    test "returns error for empty path" do
      assert {:error, _} = Validators.validate_path("")
    end

    test "returns :ok for nil" do
      assert Validators.validate_path(nil) == :ok
    end

    test "allows paths with special characters" do
      assert Validators.validate_path("/var/app-name_1.0") == :ok
    end
  end

  describe "validate_mode/1" do
    test "returns :ok for nil" do
      assert Validators.validate_mode(nil) == :ok
    end

    test "returns :ok for 0o644" do
      assert Validators.validate_mode(0o644) == :ok
    end

    test "returns :ok for 0o755" do
      assert Validators.validate_mode(0o755) == :ok
    end

    test "returns :ok for 0" do
      assert Validators.validate_mode(0) == :ok
    end

    test "returns :ok for 0o7777 (maximum)" do
      assert Validators.validate_mode(0o7777) == :ok
    end

    test "returns error for mode greater than 0o7777" do
      assert {:error, msg} = Validators.validate_mode(0o10000)
      assert msg =~ "invalid mode"
    end

    test "returns error for negative mode" do
      assert {:error, msg} = Validators.validate_mode(-1)
      assert msg =~ "invalid mode"
    end
  end

  describe "validate_name/1" do
    test "returns :ok for valid name" do
      assert Validators.validate_name("nginx") == :ok
    end

    test "returns :ok for name with numbers" do
      assert Validators.validate_name("nginx123") == :ok
    end

    test "returns :ok for name with dots" do
      assert Validators.validate_name("php8.1") == :ok
    end

    test "returns :ok for name with underscores" do
      assert Validators.validate_name("my_package") == :ok
    end

    test "returns :ok for name with hyphens" do
      assert Validators.validate_name("my-package") == :ok
    end

    test "returns error for name with shell metacharacters" do
      assert {:error, _} = Validators.validate_name("bad;rm")
    end

    test "returns error for empty name" do
      assert {:error, _} = Validators.validate_name("")
    end

    test "returns :ok for nil" do
      assert Validators.validate_name(nil) == :ok
    end
  end

  describe "validate_names/1" do
    test "returns :ok for list of valid names" do
      assert Validators.validate_names(["nginx", "curl", "vim"]) == :ok
    end

    test "returns :ok for empty list" do
      assert Validators.validate_names([]) == :ok
    end

    test "returns error if any name is invalid" do
      assert {:error, _} = Validators.validate_names(["nginx", "bad;rm", "curl"])
    end

    test "only accepts list argument" do
      # validate_names requires a list, nil will raise FunctionClauseError
      assert_raise FunctionClauseError, fn ->
        Validators.validate_names(nil)
      end
    end
  end

  describe "validate_username/1" do
    test "returns :ok for valid username" do
      assert Validators.validate_username("deploy") == :ok
    end

    test "returns :ok for username with underscore prefix" do
      assert Validators.validate_username("_nginx") == :ok
    end

    test "returns :ok for username with numbers" do
      assert Validators.validate_username("user1") == :ok
    end

    test "returns error for username starting with number" do
      assert {:error, _} = Validators.validate_username("1user")
    end

    test "returns error for username with special characters" do
      assert {:error, _} = Validators.validate_username("user@domain")
    end

    test "returns :ok for nil" do
      assert Validators.validate_username(nil) == :ok
    end
  end

  describe "validate_id/1" do
    test "returns :ok for positive integer" do
      assert Validators.validate_id(1001) == :ok
    end

    test "returns :ok for zero" do
      assert Validators.validate_id(0) == :ok
    end

    test "returns error for negative integer" do
      assert {:error, _} = Validators.validate_id(-1)
    end

    test "returns :ok for nil" do
      assert Validators.validate_id(nil) == :ok
    end
  end

  describe "validate_shell/1" do
    test "returns :ok for absolute shell path" do
      assert Validators.validate_shell("/bin/bash") == :ok
    end

    test "returns :ok for nologin shell" do
      assert Validators.validate_shell("/usr/sbin/nologin") == :ok
    end

    test "returns error for relative shell path" do
      assert {:error, _} = Validators.validate_shell("bash")
    end

    test "returns :ok for nil" do
      assert Validators.validate_shell(nil) == :ok
    end
  end

  describe "validate_state/2" do
    test "returns :ok for valid state" do
      assert Validators.validate_state(:present, [:present, :absent]) == :ok
    end

    test "returns :ok for another valid state" do
      assert Validators.validate_state(:absent, [:present, :absent]) == :ok
    end

    test "returns error for invalid state" do
      assert {:error, msg} = Validators.validate_state(:unknown, [:present, :absent])
      assert msg =~ "invalid state"
    end
  end

  describe "validate_all/1" do
    test "returns :ok when all validations pass" do
      validations = [
        fn -> :ok end,
        fn -> :ok end,
        fn -> :ok end
      ]

      assert Validators.validate_all(validations) == :ok
    end

    test "returns first error when validation fails" do
      validations = [
        fn -> :ok end,
        fn -> {:error, "first error"} end,
        fn -> {:error, "second error"} end
      ]

      assert Validators.validate_all(validations) == {:error, "first error"}
    end

    test "returns :ok for empty list" do
      assert Validators.validate_all([]) == :ok
    end

    test "short-circuits on first error" do
      # The third function should not be called
      validations = [
        fn -> :ok end,
        fn -> {:error, "error"} end,
        fn -> raise "should not be called" end
      ]

      assert Validators.validate_all(validations) == {:error, "error"}
    end
  end
end

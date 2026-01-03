defmodule Nexus.Resources.Providers.User do
  @moduledoc """
  User provider selector.

  Routes to the appropriate user management implementation based on OS.
  - Linux/BSD: Uses useradd/usermod commands
  - macOS: Uses dscl (Directory Service command line)
  """

  alias Nexus.Resources.Providers.User.{Darwin, Linux}

  # Linux-like systems using useradd/usermod
  @linux_families [:debian, :rhel, :arch, :alpine, :freebsd]

  @doc """
  Returns the appropriate user provider for the given facts.
  """
  @spec provider_for(map()) :: {:ok, module()} | {:error, term()}
  def provider_for(%{os: :darwin}), do: {:ok, Darwin}
  def provider_for(%{os: :linux}), do: {:ok, Linux}
  def provider_for(%{os_family: :darwin}), do: {:ok, Darwin}
  def provider_for(%{os_family: family}) when family in @linux_families, do: {:ok, Linux}
  def provider_for(%{os_family: family}), do: {:error, {:unsupported_os, family}}
  def provider_for(_), do: {:error, :unknown_os}
end

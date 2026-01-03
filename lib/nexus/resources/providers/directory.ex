defmodule Nexus.Resources.Providers.Directory do
  @moduledoc """
  Directory provider selector.

  Routes to the appropriate directory management implementation.
  Currently only Unix is supported (Linux, macOS, BSD).
  """

  alias Nexus.Resources.Providers.Directory.Unix

  # Unix-like operating systems
  @unix_os [:linux, :darwin, :freebsd, :openbsd, :netbsd]
  @unix_families [:debian, :rhel, :arch, :alpine, :darwin, :freebsd]

  @doc """
  Returns the appropriate directory provider for the given facts.
  """
  @spec provider_for(map()) :: {:ok, module()} | {:error, term()}
  def provider_for(%{os: os}) when os in @unix_os, do: {:ok, Unix}
  def provider_for(%{os_family: family}) when family in @unix_families, do: {:ok, Unix}
  def provider_for(%{os_family: family}), do: {:error, {:unsupported_os, family}}
  def provider_for(_), do: {:error, :unknown_os}
end

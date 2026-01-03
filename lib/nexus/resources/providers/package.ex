defmodule Nexus.Resources.Providers.Package do
  @moduledoc """
  Package provider selector.

  Routes to the appropriate package manager implementation
  based on the target host's OS family.

  ## Supported Package Managers

  | OS Family | Provider | Package Manager |
  |-----------|----------|-----------------|
  | debian    | Apt      | apt-get         |
  | rhel      | Yum      | yum/dnf         |
  | arch      | Pacman   | pacman          |
  | alpine    | Apk      | apk             |
  | darwin    | Brew     | homebrew        |
  | suse      | Zypper   | zypper          |

  """

  alias Nexus.Resources.Providers.Package.{Apt, Brew, Pacman, Yum}

  @doc """
  Returns the appropriate package provider for the given facts.

  ## Examples

      iex> Package.provider_for(%{os_family: :debian})
      {:ok, Nexus.Resources.Providers.Package.Apt}

      iex> Package.provider_for(%{os_family: :rhel})
      {:ok, Nexus.Resources.Providers.Package.Yum}

      iex> Package.provider_for(%{os_family: :unknown})
      {:error, {:unsupported_os, :unknown}}

  """
  @spec provider_for(map()) :: {:ok, module()} | {:error, term()}
  def provider_for(%{os_family: :debian}), do: {:ok, Apt}
  def provider_for(%{os_family: :rhel}), do: {:ok, Yum}
  def provider_for(%{os_family: :arch}), do: {:ok, Pacman}
  def provider_for(%{os_family: :darwin}), do: {:ok, Brew}
  # def provider_for(%{os_family: :alpine}), do: {:ok, Apk}
  # def provider_for(%{os_family: :suse}), do: {:ok, Zypper}
  def provider_for(%{os_family: family}), do: {:error, {:unsupported_os, family}}
  def provider_for(_), do: {:error, :unknown_os}
end

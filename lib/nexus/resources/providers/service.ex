defmodule Nexus.Resources.Providers.Service do
  @moduledoc """
  Service provider selector.

  Routes to the appropriate init system implementation
  based on the target host's OS.

  ## Supported Init Systems

  | OS Family | Provider | Init System |
  |-----------|----------|-------------|
  | debian    | Systemd  | systemd     |
  | rhel      | Systemd  | systemd     |
  | arch      | Systemd  | systemd     |
  | darwin    | Launchd  | launchd     |
  | alpine    | OpenRC   | openrc      |

  """

  alias Nexus.Resources.Providers.Service.{Launchd, Systemd}

  @doc """
  Returns the appropriate service provider for the given facts.

  ## Examples

      iex> Service.provider_for(%{os: :linux, os_family: :debian})
      {:ok, Nexus.Resources.Providers.Service.Systemd}

      iex> Service.provider_for(%{os: :darwin})
      {:ok, Nexus.Resources.Providers.Service.Launchd}

  """
  @spec provider_for(map()) :: {:ok, module()} | {:error, term()}
  def provider_for(%{os: :darwin}), do: {:ok, Launchd}
  def provider_for(%{os: :linux}), do: {:ok, Systemd}
  def provider_for(%{os_family: :debian}), do: {:ok, Systemd}
  def provider_for(%{os_family: :rhel}), do: {:ok, Systemd}
  def provider_for(%{os_family: :arch}), do: {:ok, Systemd}
  # def provider_for(%{os_family: :alpine}), do: {:ok, OpenRC}
  def provider_for(%{os_family: family}), do: {:error, {:unsupported_os, family}}
  def provider_for(_), do: {:error, :unknown_os}
end

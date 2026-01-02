defmodule Nexus.Template.Renderer do
  @moduledoc """
  Renders EEx templates with variable bindings.

  Provides safe template rendering with proper error handling
  and support for both file-based and string-based templates.

  ## Examples

      # Render from file
      {:ok, content} = Renderer.render_file("templates/nginx.conf.eex", %{port: 8080})

      # Render from string
      {:ok, content} = Renderer.render_string("<%= @name %>", %{name: "World"})

  """

  @doc """
  Renders an EEx template file with the given variables.

  Variables are available in the template as `@var_name`.

  ## Examples

      # template.eex contains: "Hello, <%= @name %>!"
      {:ok, "Hello, World!"} = Renderer.render_file("template.eex", %{name: "World"})

  """
  @spec render_file(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def render_file(path, vars \\ %{}) when is_binary(path) and is_map(vars) do
    expanded_path = Path.expand(path)

    case File.read(expanded_path) do
      {:ok, template} ->
        render_string(template, vars)

      {:error, reason} ->
        {:error, {:template_file_error, path, reason}}
    end
  end

  @doc """
  Renders an EEx template string with the given variables.

  Variables are available in the template as `@var_name`.

  ## Examples

      {:ok, "Port: 8080"} = Renderer.render_string("Port: <%= @port %>", %{port: 8080})

  """
  @spec render_string(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def render_string(template, vars \\ %{}) when is_binary(template) and is_map(vars) do
    do_render_string(template, vars)
  end

  # sobelow_skip ["RCE.EEx"]
  defp do_render_string(template, vars) do
    bindings = build_bindings(vars)
    # Template content comes from user-controlled files (nexus.exs)
    # This is intentional - users define their own templates
    result = EEx.eval_string(template, bindings)
    {:ok, result}
  rescue
    e in EEx.SyntaxError ->
      {:error, {:template_syntax_error, Exception.message(e)}}

    e in CompileError ->
      {:error, {:template_compile_error, Exception.message(e)}}

    e in KeyError ->
      {:error, {:template_missing_var, e.key}}

    e ->
      {:error, {:template_error, Exception.message(e)}}
  end

  @doc """
  Checks if a template file exists and is readable.

  ## Examples

      true = Renderer.template_exists?("templates/nginx.conf.eex")
      false = Renderer.template_exists?("nonexistent.eex")

  """
  @spec template_exists?(String.t()) :: boolean()
  def template_exists?(path) when is_binary(path) do
    path
    |> Path.expand()
    |> File.exists?()
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_bindings(vars) do
    # Convert map to keyword list with :assigns key for @ syntax
    assigns =
      vars
      |> Enum.map(fn {k, v} -> {to_atom(k), v} end)
      |> Enum.into([])

    [assigns: assigns]
  end

  defp to_atom(key) when is_atom(key), do: key
  defp to_atom(key) when is_binary(key), do: String.to_atom(key)
end

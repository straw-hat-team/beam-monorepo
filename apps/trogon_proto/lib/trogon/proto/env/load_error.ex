defmodule Trogon.Proto.Env.LoadError do
  @moduledoc """
  Raised when one or more environment variables fail to load.

  Aggregates every failure encountered while loading a configuration so the
  caller can fix all problems at once instead of one per run.
  """

  defexception [:errors]

  @type error :: %{
          required(:env_var) => String.t(),
          required(:field) => atom(),
          required(:reason) => :missing | {:invalid, String.t()}
        }

  @type t :: %__MODULE__{errors: [error()]}

  @impl true
  def message(%__MODULE__{} = err) do
    header = "failed to load #{length(err.errors)} environment variable(s):"
    header <> "\n" <> Enum.map_join(err.errors, "\n", &format_error/1) <> "\n"
  end

  defp format_error(%{env_var: name, reason: :missing}) do
    "  - #{name} missing"
  end

  defp format_error(%{env_var: name, reason: {:invalid, reason}}) do
    "  - #{name} invalid (#{reason})"
  end
end

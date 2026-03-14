defmodule Trogon.Commanded.ConsistencyPolicy.TimeoutError do
  @moduledoc """
  Consistency check timed out waiting for the required version.
  """

  alias Trogon.Commanded.ConsistencyPolicy.{ExactVersionPolicy, MinVersionPolicy}

  defexception [:policy, :elapsed_ms, :attempts]

  @typedoc "Policy that timed out."
  @type policy :: MinVersionPolicy.t() | ExactVersionPolicy.t()

  @typedoc "Time spent retrying before timeout, in milliseconds."
  @type elapsed_ms :: pos_integer()

  @typedoc "Number of query attempts made."
  @type attempts :: non_neg_integer()

  @typedoc "Raised when the consistency check times out."
  @type t :: %__MODULE__{
          policy: policy(),
          elapsed_ms: elapsed_ms(),
          attempts: attempts()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      policy: Keyword.fetch!(opts, :policy),
      elapsed_ms: Keyword.fetch!(opts, :elapsed_ms),
      attempts: Keyword.fetch!(opts, :attempts)
    }
  end

  @impl Exception
  def message(%__MODULE__{} = error) do
    "Consistency timeout: failed to #{verb_for(error.policy)} version #{error.policy.version} within #{error.elapsed_ms}ms after #{error.attempts} attempts"
  end

  defp verb_for(%MinVersionPolicy{}), do: "reach"
  defp verb_for(%ExactVersionPolicy{}), do: "reach exact"
end

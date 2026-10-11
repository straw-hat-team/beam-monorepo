defmodule Trogon.Commanded.ConsistencyPolicy.VersionMismatchError do
  @moduledoc """
  Requested version does not match the current version.
  """

  alias Trogon.Commanded.ConsistencyPolicy.ExactVersionPolicy

  defexception [:policy, :current_version]

  @typedoc "Policy that required exact version."
  @type policy :: ExactVersionPolicy.t()

  @typedoc "Version the projection is at (has moved past requested)."
  @type current_version :: non_neg_integer()

  @typedoc "Raised when the projection version does not match the policy requirement."
  @type t :: %__MODULE__{
          policy: policy(),
          current_version: current_version()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      policy: Keyword.fetch!(opts, :policy),
      current_version: Keyword.fetch!(opts, :current_version)
    }
  end

  @impl Exception
  def message(%__MODULE__{} = error) do
    "Consistency version mismatch: requested version #{error.policy.version} but current version is #{error.current_version}"
  end
end

defmodule Trogon.Commanded.ConsistencyPolicy.MinVersionPolicy do
  @moduledoc """
  Consistency policy that retries until `projection.version >= required_version`.
  """

  alias Trogon.Commanded.Helpers

  @enforce_keys [:version, :timeout, :delay]
  defstruct [:version, :timeout, :delay]

  @typedoc "Required projection version (event stream position)."
  @type version :: non_neg_integer()

  @typedoc "Positive integer milliseconds."
  @type milliseconds :: pos_integer()

  @typedoc "Retries until projection.version >= required version."
  @type t :: %__MODULE__{
          version: version(),
          timeout: milliseconds(),
          delay: milliseconds()
        }

  @typedoc "Options for `new!/1`. Accepts Duration or integer milliseconds for timeout/delay."
  @type opts :: %{
          required(:version) => version(),
          required(:timeout) => Duration.t() | milliseconds(),
          required(:delay) => Duration.t() | milliseconds()
        }

  @spec new!(opts()) :: t()
  def new!(%{version: version, timeout: timeout, delay: delay})
      when is_integer(version) and version >= 0 do
    %__MODULE__{
      version: version,
      timeout: Helpers.to_timeout(timeout, :timeout),
      delay: Helpers.to_timeout(delay, :delay)
    }
  end

  if Code.ensure_loaded?(TrogonProto.Consistency.V1Alpha1.Consistency) do
    alias Google.Protobuf
    alias TrogonProto.Consistency.V1Alpha1.{Consistency, MinVersion}

    @default_timeout_ms 5_000
    @default_delay_ms 100

    @doc """
    Build policy from protobuf Consistency with min_version requirement.

    Uses defaults (5s, 100ms) when proto omits durations.
    """
    @spec from_proto(Consistency.t()) :: t()
    def from_proto(%Consistency{requirement: {:min_version, %MinVersion{} = min_version}} = proto) do
      new!(%{
        version: min_version.version,
        timeout: Helpers.to_duration_or(proto.timeout_duration, @default_timeout_ms),
        delay: Helpers.to_duration_or(proto.delay_duration, @default_delay_ms)
      })
    end

    @doc """
    Convert policy to protobuf Consistency.
    """
    @spec to_proto(t()) :: Consistency.t()
    def to_proto(%__MODULE__{} = policy) do
      timeout_duration = policy.timeout |> Helpers.ms_to_duration() |> Protobuf.from_duration()
      delay_duration = policy.delay |> Helpers.ms_to_duration() |> Protobuf.from_duration()

      %Consistency{
        requirement: {:min_version, %MinVersion{version: policy.version}},
        timeout_duration: timeout_duration,
        delay_duration: delay_duration
      }
    end
  end
end

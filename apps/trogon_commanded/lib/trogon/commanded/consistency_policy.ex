defmodule Trogon.Commanded.ConsistencyPolicy do
  @moduledoc """
  Eventual consistency policy for projection queries with read-after-write guarantees.

  Waits for projections to reach a required consistency level before returning
  query results, enabling proper read-after-write semantics in eventually
  consistent systems.

  ## Policy types

  - `MinVersionPolicy` - Retries until `projection.version >= required_version`
  - `ExactVersionPolicy` - Returns only if `projection.version == required_version`

  ## Examples

      alias Trogon.Commanded.ConsistencyPolicy
      alias Trogon.Commanded.ConsistencyPolicy.{MinVersionPolicy, ExactVersionPolicy, VersionedData}

      # Integer milliseconds
      policy = MinVersionPolicy.new!(%{version: 5, timeout: 5000, delay: 100})

      # Or Duration
      policy = MinVersionPolicy.new!(%{
        version: 5,
        timeout: Duration.new!(second: 5),
        delay: 100
      })

      {:ok, order} = ConsistencyPolicy.run(policy, fn ->
        order = Repo.get(OrderProjection, order_id)
        stream_version = order.version
        {:ok, VersionedData.new(stream_version, order)}
      end)

      # No consistency requirement
      {:ok, data} = ConsistencyPolicy.run(nil, fn ->
        result = Repo.get(OrderProjection, order_id)
        {:ok, VersionedData.new(0, result)}
      end)
  """

  alias Trogon.Commanded.ConsistencyPolicy.{
    MinVersionPolicy,
    ExactVersionPolicy,
    VersionedData,
    TimeoutError,
    VersionMismatchError
  }

  @typedoc "Event stream version (projection position)."
  @type version :: non_neg_integer()

  @typedoc "Positive integer representing milliseconds."
  @type milliseconds :: pos_integer()

  @typedoc "MinVersionPolicy or ExactVersionPolicy."
  @type t :: MinVersionPolicy.t() | ExactVersionPolicy.t()

  @typedoc "Policy or nil (no consistency check)."
  @type policy :: t() | nil

  @typedoc "Callback function triggered by the policy."
  @type callback_fn :: (-> {:ok, VersionedData.t()} | {:error, term()})

  @doc """
  Normalize timeout/delay to Duration.

  Accepts a positive integer (milliseconds) or a Duration struct.
  """
  @spec to_duration(milliseconds() | Duration.t()) :: Duration.t()
  def to_duration(ms) when is_integer(ms) and ms > 0 do
    Trogon.Commanded.Helpers.ms_to_duration(ms)
  end

  def to_duration(%Duration{} = d) do
    d
  end

  @doc """
  Run a query under this policy.

  Retries until consistency requirements are met or timeout.
  """
  @spec run(policy(), callback_fn()) ::
          {:ok, term()}
          | {:error, TimeoutError.t()}
          | {:error, VersionMismatchError.t()}
          | {:error, term()}
  def run(nil, callback_fn) when is_function(callback_fn, 0) do
    case callback_fn.() do
      {:ok, %VersionedData{} = result} -> {:ok, result.data}
      {:error, reason} -> {:error, reason}
    end
  end

  def run(policy, callback_fn) when is_function(callback_fn, 0) do
    start_time = System.monotonic_time(:millisecond)
    deadline = start_time + Kernel.to_timeout(policy.timeout)
    delay_ms = Kernel.to_timeout(policy.delay)

    case do_retry(policy, callback_fn, deadline, start_time, delay_ms, 1) do
      {:ok, %VersionedData{} = result} -> {:ok, result.data}
      {:error, reason} -> {:error, reason}
    end
  end

  if Code.ensure_loaded?(TrogonProto.Consistency.V1Alpha1.Consistency) do
    alias TrogonProto.Consistency.V1Alpha1.Consistency

    @doc """
    Build policy from protobuf Consistency.

    Returns `nil` if proto is nil or has no requirement.
    Dispatches to the appropriate policy based on the requirement type.
    """
    @spec from_proto(Consistency.t() | nil) :: policy()
    def from_proto(nil) do
      nil
    end

    def from_proto(%Consistency{requirement: nil}) do
      nil
    end

    def from_proto(%Consistency{requirement: {:min_version, _}} = proto) do
      MinVersionPolicy.from_proto(proto)
    end

    def from_proto(%Consistency{requirement: {:exact_version, _}} = proto) do
      ExactVersionPolicy.from_proto(proto)
    end

    @doc """
    Convert policy to protobuf Consistency.

    Dispatches to the appropriate policy's to_proto/1.
    """
    @spec to_proto(t()) :: Consistency.t()
    def to_proto(%MinVersionPolicy{} = policy) do
      MinVersionPolicy.to_proto(policy)
    end

    def to_proto(%ExactVersionPolicy{} = policy) do
      ExactVersionPolicy.to_proto(policy)
    end
  end

  defp do_retry(policy, callback_fn, deadline, start_time, delay_ms, attempt) do
    with {:ok, %VersionedData{} = result} <- callback_fn.() do
      case {policy, result.version} do
        {%MinVersionPolicy{}, v} when v >= policy.version ->
          {:ok, result}

        {%ExactVersionPolicy{}, v} when v == policy.version ->
          {:ok, result}

        {%ExactVersionPolicy{}, v} when v > policy.version ->
          {:error,
           VersionMismatchError.exception(
             policy: policy,
             current_version: v
           )}

        _ ->
          retry_or_timeout(policy, callback_fn, deadline, start_time, delay_ms, attempt)
      end
    end
  end

  defp retry_or_timeout(policy, callback_fn, deadline, start_time, delay_ms, attempt) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      elapsed_ms = now - start_time

      {:error,
       TimeoutError.exception(
         policy: policy,
         elapsed_ms: elapsed_ms,
         attempts: attempt
       )}
    else
      remaining_ms = max(deadline - now, 0)
      Process.sleep(min(delay_ms, remaining_ms))
      do_retry(policy, callback_fn, deadline, start_time, delay_ms, attempt + 1)
    end
  end
end

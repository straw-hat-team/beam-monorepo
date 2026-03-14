defmodule Trogon.Commanded.ConsistencyPolicyTest do
  use ExUnit.Case, async: true

  alias Trogon.Commanded.ConsistencyPolicy

  alias Trogon.Commanded.ConsistencyPolicy.{
    MinVersionPolicy,
    ExactVersionPolicy,
    VersionedData,
    TimeoutError,
    VersionMismatchError
  }

  describe "to_duration/1" do
    test "converts integer milliseconds to Duration" do
      assert Kernel.to_timeout(ConsistencyPolicy.to_duration(100)) == 100
      assert Kernel.to_timeout(ConsistencyPolicy.to_duration(1000)) == 1000
      assert Kernel.to_timeout(ConsistencyPolicy.to_duration(1500)) == 1500
      assert Kernel.to_timeout(ConsistencyPolicy.to_duration(1)) == 1
    end

    test "passes through Duration unchanged" do
      duration = Duration.new!(second: 5)
      assert ConsistencyPolicy.to_duration(duration) == duration
    end
  end

  describe "TimeoutError" do
    test "creates error with min_version policy" do
      policy = MinVersionPolicy.new!(%{version: 5, timeout: 5000, delay: 100})

      error =
        TimeoutError.exception(
          policy: policy,
          elapsed_ms: 1000,
          attempts: 3
        )

      assert error.policy == policy
      assert error.elapsed_ms == 1000
      assert error.attempts == 3
      assert Exception.message(error) =~ "failed to reach version 5"
    end

    test "creates error with exact_version policy" do
      policy = ExactVersionPolicy.new!(%{version: 5, timeout: 5000, delay: 100})

      error =
        TimeoutError.exception(
          policy: policy,
          elapsed_ms: 500,
          attempts: 2
        )

      assert error.policy == policy
      assert Exception.message(error) =~ "failed to reach exact version 5"
    end
  end

  describe "VersionMismatchError" do
    test "creates error with policy and current_version" do
      policy = ExactVersionPolicy.new!(%{version: 5, timeout: 5000, delay: 100})

      error = VersionMismatchError.exception(policy: policy, current_version: 7)

      assert error.policy == policy
      assert error.current_version == 7
      assert Exception.message(error) =~ "version 5"
    end
  end

  describe "run/2" do
    test "returns data when no consistency config provided" do
      query_fn = fn ->
        {:ok, VersionedData.new(5, %{id: "123"})}
      end

      assert {:ok, %{id: "123"}} = ConsistencyPolicy.run(nil, query_fn)
    end

    test "propagates error when no consistency config provided" do
      query_fn = fn -> {:error, :not_found} end

      assert {:error, :not_found} = ConsistencyPolicy.run(nil, query_fn)
    end

    test "returns data when version matches min_version" do
      policy =
        MinVersionPolicy.new!(%{
          version: 5,
          timeout: Duration.new!(second: 1),
          delay: 100
        })

      query_fn = fn ->
        {:ok, VersionedData.new(5, %{id: "123"})}
      end

      assert {:ok, %{id: "123"}} = ConsistencyPolicy.run(policy, query_fn)
    end

    test "returns data when version exceeds min_version" do
      policy =
        MinVersionPolicy.new!(%{
          version: 5,
          timeout: Duration.new!(second: 1),
          delay: 100
        })

      query_fn = fn ->
        {:ok, VersionedData.new(7, %{id: "123"})}
      end

      assert {:ok, %{id: "123"}} = ConsistencyPolicy.run(policy, query_fn)
    end

    test "returns timeout error when version never reaches min_version" do
      policy =
        MinVersionPolicy.new!(%{
          version: 5,
          timeout: 100,
          delay: 20
        })

      query_fn = fn ->
        {:ok, VersionedData.new(3, %{id: "123"})}
      end

      assert {:error, %TimeoutError{policy: %MinVersionPolicy{version: 5}}} =
               ConsistencyPolicy.run(policy, query_fn)
    end

    test "returns timeout error with exact_version when ExactVersionPolicy times out" do
      policy =
        ExactVersionPolicy.new!(%{
          version: 5,
          timeout: 100,
          delay: 20
        })

      query_fn = fn ->
        {:ok, VersionedData.new(3, %{id: "123"})}
      end

      assert {:error, %TimeoutError{policy: %ExactVersionPolicy{version: 5}}} =
               ConsistencyPolicy.run(policy, query_fn)
    end

    test "returns data when exact_version matches" do
      policy =
        ExactVersionPolicy.new!(%{
          version: 5,
          timeout: Duration.new!(second: 1),
          delay: 100
        })

      query_fn = fn ->
        {:ok, VersionedData.new(5, %{id: "123"})}
      end

      assert {:ok, %{id: "123"}} = ConsistencyPolicy.run(policy, query_fn)
    end

    test "returns version mismatch error when version exceeds exact_version" do
      policy =
        ExactVersionPolicy.new!(%{
          version: 5,
          timeout: Duration.new!(second: 1),
          delay: 100
        })

      query_fn = fn ->
        {:ok, VersionedData.new(7, %{id: "123"})}
      end

      assert {:error, %VersionMismatchError{}} =
               ConsistencyPolicy.run(policy, query_fn)
    end

    test "propagates query errors" do
      policy =
        MinVersionPolicy.new!(%{
          version: 5,
          timeout: Duration.new!(second: 1),
          delay: 100
        })

      query_fn = fn ->
        {:error, :not_found}
      end

      assert {:error, :not_found} = ConsistencyPolicy.run(policy, query_fn)
    end

    test "accepts closure with bound variable" do
      policy =
        MinVersionPolicy.new!(%{
          version: 5,
          timeout: Duration.new!(second: 1),
          delay: 100
        })

      order_id = "ord-acme-001"

      assert {:ok, %{id: "ord-acme-001"}} =
               ConsistencyPolicy.run(policy, fn -> fetch_order_by_id(order_id) end)
    end

    test "accepts capture of 0-arity function" do
      policy =
        MinVersionPolicy.new!(%{
          version: 5,
          timeout: Duration.new!(second: 1),
          delay: 100
        })

      assert {:ok, %{id: "acme-default"}} =
               ConsistencyPolicy.run(policy, &Trogon.Commanded.ConsistencyPolicyTest.fetch_order/0)
    end
  end

  defp fetch_order_by_id(order_id) do
    {:ok, VersionedData.new(5, %{id: order_id})}
  end

  def fetch_order do
    {:ok, VersionedData.new(5, %{id: "acme-default"})}
  end

  if Code.ensure_loaded?(TrogonProto.Consistency.V1Alpha1.Consistency) do
    alias TrogonProto.Consistency.V1Alpha1.{Consistency, MinVersion, ExactVersion}

    describe "from_proto/1" do
      test "returns nil for nil input" do
        assert ConsistencyPolicy.from_proto(nil) == nil
      end

      test "returns nil when requirement is nil" do
        proto = %Consistency{requirement: nil}
        assert ConsistencyPolicy.from_proto(proto) == nil
      end

      test "dispatches min_version to MinVersionPolicy" do
        proto = %Consistency{
          requirement: {:min_version, %MinVersion{version: 5}},
          timeout_duration: Google.Protobuf.from_duration(Duration.new!(second: 1)),
          delay_duration: Google.Protobuf.from_duration(ConsistencyPolicy.to_duration(100))
        }

        assert %MinVersionPolicy{version: 5} = ConsistencyPolicy.from_proto(proto)
      end

      test "dispatches exact_version to ExactVersionPolicy" do
        proto = %Consistency{
          requirement: {:exact_version, %ExactVersion{version: 5}},
          timeout_duration: Google.Protobuf.from_duration(Duration.new!(second: 1)),
          delay_duration: Google.Protobuf.from_duration(ConsistencyPolicy.to_duration(100))
        }

        assert %ExactVersionPolicy{version: 5} = ConsistencyPolicy.from_proto(proto)
      end
    end

    describe "to_proto/1" do
      test "converts MinVersionPolicy to proto" do
        policy =
          MinVersionPolicy.new!(%{
            version: 5,
            timeout: Duration.new!(second: 1),
            delay: 100
          })

        proto = ConsistencyPolicy.to_proto(policy)

        assert {:min_version, %MinVersion{version: 5}} = proto.requirement
      end

      test "converts ExactVersionPolicy to proto" do
        policy =
          ExactVersionPolicy.new!(%{
            version: 5,
            timeout: Duration.new!(second: 1),
            delay: 100
          })

        proto = ConsistencyPolicy.to_proto(policy)

        assert {:exact_version, %ExactVersion{version: 5}} = proto.requirement
      end
    end
  end
end

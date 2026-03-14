defmodule Trogon.Commanded.ConsistencyPolicy.MinVersionPolicyTest do
  use ExUnit.Case, async: true

  alias Trogon.Commanded.ConsistencyPolicy.MinVersionPolicy

  describe "new!/1" do
    test "creates policy with Duration opts" do
      policy =
        MinVersionPolicy.new!(%{
          version: 5,
          timeout: Duration.new!(second: 1),
          delay: 100
        })

      assert %MinVersionPolicy{version: 5} = policy
      assert Kernel.to_timeout(policy.timeout) == 1000
      assert Kernel.to_timeout(policy.delay) == 100
    end

    test "creates policy with integer milliseconds" do
      policy = MinVersionPolicy.new!(%{version: 5, timeout: 1000, delay: 100})

      assert %MinVersionPolicy{version: 5} = policy
      assert Kernel.to_timeout(policy.timeout) == 1000
      assert Kernel.to_timeout(policy.delay) == 100
    end
  end

  if Code.ensure_loaded?(TrogonProto.Consistency.V1Alpha1.Consistency) do
    alias Trogon.Commanded.ConsistencyPolicy
    alias TrogonProto.Consistency.V1Alpha1.{Consistency, MinVersion}

    describe "from_proto/1" do
      test "converts proto to policy" do
        proto = %Consistency{
          requirement: {:min_version, %MinVersion{version: 5}},
          timeout_duration: Google.Protobuf.from_duration(Duration.new!(second: 1)),
          delay_duration: Google.Protobuf.from_duration(ConsistencyPolicy.to_duration(100))
        }

        policy = MinVersionPolicy.from_proto(proto)
        assert %MinVersionPolicy{version: 5} = policy
        assert Kernel.to_timeout(policy.timeout) == 1000
        assert Kernel.to_timeout(policy.delay) == 100
      end

      test "uses defaults when proto omits durations" do
        proto = %Consistency{
          requirement: {:min_version, %MinVersion{version: 5}},
          timeout_duration: nil,
          delay_duration: nil
        }

        policy = MinVersionPolicy.from_proto(proto)
        assert %MinVersionPolicy{version: 5} = policy
        assert Kernel.to_timeout(policy.timeout) == 5000
        assert Kernel.to_timeout(policy.delay) == 100
      end
    end

    describe "to_proto/1" do
      test "creates proto" do
        policy =
          MinVersionPolicy.new!(%{
            version: 5,
            timeout: Duration.new!(second: 1),
            delay: 100
          })

        proto = MinVersionPolicy.to_proto(policy)

        assert %Consistency{} = proto
        assert {:min_version, %MinVersion{version: 5}} = proto.requirement
        assert proto.timeout_duration == Google.Protobuf.from_duration(Duration.new!(second: 1))
        assert proto.delay_duration == Google.Protobuf.from_duration(ConsistencyPolicy.to_duration(100))
      end
    end
  end
end

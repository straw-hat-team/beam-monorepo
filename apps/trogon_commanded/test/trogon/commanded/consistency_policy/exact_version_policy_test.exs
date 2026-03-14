defmodule Trogon.Commanded.ConsistencyPolicy.ExactVersionPolicyTest do
  use ExUnit.Case, async: true

  alias Trogon.Commanded.ConsistencyPolicy.ExactVersionPolicy

  describe "new!/1" do
    test "creates policy with Duration opts" do
      policy =
        ExactVersionPolicy.new!(%{
          version: 5,
          timeout: Duration.new!(second: 1),
          delay: 100
        })

      assert %ExactVersionPolicy{version: 5} = policy
      assert Kernel.to_timeout(policy.timeout) == 1000
      assert Kernel.to_timeout(policy.delay) == 100
    end

    test "creates policy with integer milliseconds" do
      policy = ExactVersionPolicy.new!(%{version: 5, timeout: 1000, delay: 100})

      assert %ExactVersionPolicy{version: 5} = policy
      assert Kernel.to_timeout(policy.timeout) == 1000
      assert Kernel.to_timeout(policy.delay) == 100
    end

    test "raises for zero timeout" do
      assert_raise ArgumentError, ~r/timeout must be positive/, fn ->
        ExactVersionPolicy.new!(%{version: 5, timeout: 0, delay: 100})
      end
    end

    test "raises for invalid timeout type" do
      assert_raise ArgumentError, ~r/timeout must be/, fn ->
        ExactVersionPolicy.new!(%{version: 5, timeout: "1s", delay: 100})
      end
    end
  end

  if Code.ensure_loaded?(TrogonProto.Consistency.V1Alpha1.Consistency) do
    alias Trogon.Commanded.ConsistencyPolicy
    alias TrogonProto.Consistency.V1Alpha1.{Consistency, ExactVersion}

    describe "from_proto/1" do
      test "converts proto to policy" do
        proto = %Consistency{
          requirement: {:exact_version, %ExactVersion{version: 5}},
          timeout_duration: Google.Protobuf.from_duration(Duration.new!(second: 1)),
          delay_duration: Google.Protobuf.from_duration(ConsistencyPolicy.to_duration(100))
        }

        policy = ExactVersionPolicy.from_proto(proto)
        assert %ExactVersionPolicy{version: 5} = policy
        assert Kernel.to_timeout(policy.timeout) == 1000
        assert Kernel.to_timeout(policy.delay) == 100
      end
    end

    describe "to_proto/1" do
      test "creates proto" do
        policy =
          ExactVersionPolicy.new!(%{
            version: 5,
            timeout: Duration.new!(second: 1),
            delay: 100
          })

        proto = ExactVersionPolicy.to_proto(policy)

        assert %Consistency{} = proto
        assert {:exact_version, %ExactVersion{version: 5}} = proto.requirement
        assert proto.timeout_duration == Google.Protobuf.from_duration(Duration.new!(second: 1))
        assert proto.delay_duration == Google.Protobuf.from_duration(ConsistencyPolicy.to_duration(100))
      end
    end
  end
end

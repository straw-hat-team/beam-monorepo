defmodule Trogon.Test.TestUUIDTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  alias Trogon.Test.MockUUID

  @uuid4 "6ba7b810-9dad-41d1-80b4-00c04fd430c8"
  @uuid7 "01a128c8-383e-7f3b-8f53-5fa308ac0d07"

  describe "stub/1" do
    test "generates real UUIDs" do
      assert {:ok, %{version: 4, format: :default}} = Uniq.UUID.info(MockUUID.uuid4(:default))
      assert {:ok, %{version: 7, format: :hex}} = Uniq.UUID.info(MockUUID.uuid7(:hex))
    end
  end

  describe "expect_uuid4/1" do
    test "returns the expected UUID" do
      TestUUID.expect_uuid4(times: 1, returns: @uuid4)

      result = MockUUID.uuid4(:default)

      assert result == @uuid4
      TestUUID.assert_received_uuid4()
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers as many calls as times" do
      TestUUID.expect_uuid4(times: 2, returns: @uuid4)

      results = [MockUUID.uuid4(:default), MockUUID.uuid4(:default)]

      assert results == [@uuid4, @uuid4]
      TestUUID.assert_received_uuid4(:default)
      TestUUID.assert_received_uuid4(:default)
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects a call past times" do
      TestUUID.expect_uuid4(returns: @uuid4)
      MockUUID.uuid4(:default)

      assert_raise Mox.UnexpectedCallError, fn -> MockUUID.uuid4(:default) end
      TestUUID.assert_received_uuid4()
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "expect_uuid7/1" do
    test "returns the expected UUID" do
      TestUUID.expect_uuid7(times: 1, returns: @uuid7)

      result = MockUUID.uuid7(:default)

      assert result == @uuid7
      TestUUID.assert_received_uuid7()
      Trogon.Test.assert_empty_mailbox()
    end

    test "returns the expected UUID in the format it was given" do
      hex = String.replace(@uuid7, "-", "")
      TestUUID.expect_uuid7(times: 1, returns: hex)

      result = MockUUID.uuid7(:hex)

      assert result == hex
      TestUUID.assert_received_uuid7(:hex)
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects a call past times" do
      TestUUID.expect_uuid7(returns: @uuid7)
      MockUUID.uuid7(:default)

      assert_raise Mox.UnexpectedCallError, fn -> MockUUID.uuid7(:default) end
      TestUUID.assert_received_uuid7()
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "Uniq.UUID contract" do
    test "rejects a format Uniq.UUID does not know, as Uniq.UUID does" do
      TestUUID.expect_uuid4(times: 1, returns: @uuid4)
      TestUUID.expect_uuid7(times: 1, returns: @uuid7)

      assert_raise FunctionClauseError, fn -> Uniq.UUID.uuid7(Enum.random([:base64])) end
      assert_raise FunctionClauseError, fn -> MockUUID.uuid4(:base64) end
      assert_raise FunctionClauseError, fn -> MockUUID.uuid7(:base64) end
    end

    test "rejects a call asking for a format returns: is not in, which Uniq.UUID never returns" do
      TestUUID.expect_uuid7(times: 1, returns: @uuid7)

      assert {:ok, %{format: :hex}} = Uniq.UUID.info(Uniq.UUID.uuid7(:hex))
      assert_raise ArgumentError, ~r/:hex format/, fn -> MockUUID.uuid7(:hex) end
    end

    test "rejects returns: of another version, which Uniq.UUID never returns" do
      assert_raise ArgumentError, ~r/version 7/, fn -> TestUUID.expect_uuid7(times: 1, returns: @uuid4) end
      assert_raise ArgumentError, ~r/version 4/, fn -> TestUUID.expect_uuid4(times: 1, returns: @uuid7) end
    end

    test "rejects returns: that is not a UUID, which Uniq.UUID never returns" do
      for value <- ["not-a-uuid", nil, 7] do
        assert_raise ArgumentError, fn -> TestUUID.expect_uuid7(times: 1, returns: value) end
      end
    end
  end

  describe "returns" do
    test "is required" do
      assert_raise KeyError, fn -> TestUUID.expect_uuid4(times: 1) end
      assert_raise KeyError, fn -> TestUUID.expect_uuid7(times: 1) end
    end
  end

  describe "uuid5/1" do
    test "returns the same version 5 UUID for the same name" do
      uuid = TestUUID.uuid5("seller-456")

      assert uuid == "853d34f8-13b3-5761-a4b2-2018ea01306e"
      assert TestUUID.uuid5("seller-456") == uuid
      assert {:ok, %{version: 5, format: :default}} = Uniq.UUID.info(uuid)
    end

    test "returns another UUID for another name" do
      assert TestUUID.uuid5("seller-456") != TestUUID.uuid5("seller-457")
    end

    test "uses the trogon_test namespace" do
      namespace = Uniq.UUID.uuid5(:url, "https://hex.pm/packages/trogon_test")

      assert TestUUID.uuid5("seller-456") == Uniq.UUID.uuid5(namespace, "seller-456")
    end

    test "rejects a name that is not a string" do
      assert_raise FunctionClauseError, fn -> TestUUID.uuid5(Enum.random([:seller])) end
    end
  end

  describe "assert_received_*" do
    test "fails on a call asking for another format" do
      TestUUID.expect_uuid4(times: 1, returns: @uuid4)
      TestUUID.expect_uuid7(times: 1, returns: @uuid7)
      MockUUID.uuid4(:default)
      MockUUID.uuid7(:default)

      assert_raise ExUnit.AssertionError, fn -> TestUUID.assert_received_uuid4(:hex) end
      assert_raise ExUnit.AssertionError, fn -> TestUUID.assert_received_uuid7(:hex) end
      TestUUID.assert_received_uuid4(:default)
      TestUUID.assert_received_uuid7(:default)
      Trogon.Test.assert_empty_mailbox()
    end

    test "fail when no call was made" do
      assert_raise ExUnit.AssertionError, fn -> TestUUID.assert_received_uuid4() end
      assert_raise ExUnit.AssertionError, fn -> TestUUID.assert_received_uuid7() end
    end
  end

  describe "process ownership" do
    test "reaches the test's $callers" do
      TestUUID.expect_uuid7(times: 1, returns: @uuid7)

      result = Task.await(Task.async(fn -> MockUUID.uuid7(:default) end))

      assert result == @uuid7
      TestUUID.assert_received_uuid7()
      Trogon.Test.assert_empty_mailbox()
    end
  end
end

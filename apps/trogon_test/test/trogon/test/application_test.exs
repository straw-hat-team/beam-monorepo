defmodule Trogon.Test.ApplicationTest do
  use ExUnit.Case, async: true

  alias Trogon.Test.Application, as: TestApplication
  alias Trogon.Test.Application.Mock

  setup {TestApplication, :stub}

  test "stub/1 reads the real Application env" do
    assert Mock.get_env(:trogon_test, :seeded_value) == "real value"
    assert Mock.get_env(:trogon_test, :does_not_exist, :default) == :default
    assert Mock.fetch_env(:trogon_test, :seeded_value) == {:ok, "real value"}
    assert Mock.fetch_env!(:trogon_test, :seeded_value) == "real value"
    assert Enum.sort(Mock.get_all_env(:trogon_test)) == Enum.sort(Application.get_all_env(:trogon_test))
  end

  describe "put_env/3" do
    test "replaces the value for the calling test" do
      assert TestApplication.put_env(:trogon_test, :seeded_value, "overridden") == :ok
      assert Mock.get_env(:trogon_test, :seeded_value) == "overridden"
      assert Mock.fetch_env!(:trogon_test, :seeded_value) == "overridden"
    end

    test "keeps earlier overrides of other keys" do
      TestApplication.put_env(:trogon_test, :seeded_value, "overridden")
      TestApplication.put_env(:trogon_test, :seeded_list, c: 3)

      assert Mock.get_env(:trogon_test, :seeded_value) == "overridden"
      assert Mock.get_env(:trogon_test, :seeded_list) == [c: 3]
    end

    test "leaves the real Application env untouched" do
      TestApplication.put_env(:trogon_test, :seeded_value, "overridden")

      assert Application.get_env(:trogon_test, :seeded_value) == "real value"
    end
  end

  describe "merge_env/3" do
    test "deep merges onto the real value" do
      TestApplication.merge_env(:trogon_test, :seeded_list, b: 20, c: 3)

      assert Mock.get_env(:trogon_test, :seeded_list) == [a: 1, b: 20, c: 3]
    end

    test "builds on an earlier override" do
      TestApplication.merge_env(:trogon_test, :seeded_list, nested: [x: 1, y: 2])
      TestApplication.merge_env(:trogon_test, :seeded_list, nested: [y: 20])

      assert Mock.get_env(:trogon_test, :seeded_list) == [a: 1, b: 2, nested: [x: 1, y: 20]]
    end

    test "replaces a non-keyword value" do
      TestApplication.merge_env(:trogon_test, :seeded_value, "replaced")

      assert Mock.get_env(:trogon_test, :seeded_value) == "replaced"
    end

    test "merges onto nothing after delete_env/2" do
      TestApplication.delete_env(:trogon_test, :seeded_list)
      TestApplication.merge_env(:trogon_test, :seeded_list, c: 3)

      assert Mock.get_env(:trogon_test, :seeded_list) == [c: 3]
    end
  end

  describe "delete_env/2" do
    test "makes the key read as missing" do
      TestApplication.delete_env(:trogon_test, :seeded_value)

      assert Mock.get_env(:trogon_test, :seeded_value, :default) == :default
      assert Mock.fetch_env(:trogon_test, :seeded_value) == :error
      refute Keyword.has_key?(Mock.get_all_env(:trogon_test), :seeded_value)

      error =
        assert_raise TestApplication.MissingEnvError, fn ->
          Mock.fetch_env!(:trogon_test, :seeded_value)
        end

      assert %{app: :trogon_test, key: :seeded_value} = error
    end

    test "put_env/3 brings the key back" do
      TestApplication.delete_env(:trogon_test, :seeded_value)
      TestApplication.put_env(:trogon_test, :seeded_value, "back")

      assert Mock.get_env(:trogon_test, :seeded_value) == "back"
    end
  end

  test "get_all_env/1 applies overrides on top of the real env" do
    TestApplication.put_env(:trogon_test, :seeded_value, "overridden")
    TestApplication.put_env(:trogon_test, :extra, :added)

    env = Mock.get_all_env(:trogon_test)

    assert env[:seeded_value] == "overridden"
    assert env[:seeded_list] == [a: 1, b: 2]
    assert env[:extra] == :added
  end

  test "overrides reach the test's $callers" do
    TestApplication.put_env(:trogon_test, :seeded_value, "overridden")

    assert Task.await(Task.async(fn -> Mock.get_env(:trogon_test, :seeded_value) end)) == "overridden"
  end

  test "overrides reach a process allowed with Mox.allow/3" do
    TestApplication.put_env(:trogon_test, :seeded_value, "overridden")
    parent = self()

    pid =
      spawn(fn ->
        receive do
          :read -> send(parent, {:read, Mock.get_env(:trogon_test, :seeded_value)})
        end
      end)

    Mox.allow(Mock, self(), pid)
    send(pid, :read)

    assert_receive {:read, "overridden"}
  end
end

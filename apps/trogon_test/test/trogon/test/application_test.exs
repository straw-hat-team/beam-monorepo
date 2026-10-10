defmodule Trogon.Test.ApplicationTest do
  use ExUnit.Case, async: true

  alias Trogon.Test.Application, as: TestApplication
  alias Trogon.Test.Application.Mock

  setup {TestApplication, :stub}

  describe "stub/1" do
    test "reads a configured key from the real Application env" do
      value = Mock.get_env(:trogon_test, :seeded_value)

      assert value == "real value"
    end

    test "falls back to the default for a key the real env does not hold" do
      value = Mock.get_env(:trogon_test, :does_not_exist, :default)

      assert value == :default
    end

    test "fetches a configured key from the real Application env" do
      result = Mock.fetch_env(:trogon_test, :seeded_value)

      assert result == {:ok, "real value"}
    end

    test "reads every key of the real Application env" do
      env = Mock.get_all_env(:trogon_test)

      assert Enum.sort(env) == Enum.sort(Application.get_all_env(:trogon_test))
    end
  end

  describe "put_env/3" do
    test "replaces the value for the calling test" do
      TestApplication.put_env(:trogon_test, :seeded_value, "overridden")

      value = Mock.fetch_env!(:trogon_test, :seeded_value)

      assert value == "overridden"
    end

    test "keeps earlier overrides of other keys" do
      TestApplication.put_env(:trogon_test, :seeded_value, "overridden")
      TestApplication.put_env(:trogon_test, :seeded_list, c: 3)

      value = Mock.get_env(:trogon_test, :seeded_value)

      assert value == "overridden"
    end

    test "leaves the real Application env untouched" do
      TestApplication.put_env(:trogon_test, :seeded_value, "overridden")

      value = Application.get_env(:trogon_test, :seeded_value)

      assert value == "real value"
    end
  end

  describe "merge_env/3" do
    test "deep merges onto the real value" do
      TestApplication.merge_env(:trogon_test, :seeded_list, b: 20, c: 3)

      value = Mock.get_env(:trogon_test, :seeded_list)

      assert value == [a: 1, b: 20, c: 3]
    end

    test "builds on an earlier override" do
      TestApplication.merge_env(:trogon_test, :seeded_list, nested: [x: 1, y: 2])
      TestApplication.merge_env(:trogon_test, :seeded_list, nested: [y: 20])

      value = Mock.get_env(:trogon_test, :seeded_list)

      assert value == [a: 1, b: 2, nested: [x: 1, y: 20]]
    end

    test "replaces a non-keyword value" do
      TestApplication.merge_env(:trogon_test, :seeded_value, "replaced")

      value = Mock.get_env(:trogon_test, :seeded_value)

      assert value == "replaced"
    end

    test "merges onto nothing after delete_env/2" do
      TestApplication.delete_env(:trogon_test, :seeded_list)
      TestApplication.merge_env(:trogon_test, :seeded_list, c: 3)

      value = Mock.get_env(:trogon_test, :seeded_list)

      assert value == [c: 3]
    end
  end

  describe "delete_env/2" do
    test "makes get_env/3 fall back to the default" do
      TestApplication.delete_env(:trogon_test, :seeded_value)

      value = Mock.get_env(:trogon_test, :seeded_value, :default)

      assert value == :default
    end

    test "makes fetch_env/2 report the key as missing" do
      TestApplication.delete_env(:trogon_test, :seeded_value)

      result = Mock.fetch_env(:trogon_test, :seeded_value)

      assert result == :error
    end

    test "leaves the key out of get_all_env/1" do
      TestApplication.delete_env(:trogon_test, :seeded_value)

      env = Mock.get_all_env(:trogon_test)

      refute Keyword.has_key?(env, :seeded_value)
    end

    test "makes fetch_env!/2 raise" do
      TestApplication.delete_env(:trogon_test, :seeded_value)

      assert_raise TestApplication.MissingEnvError,
                   ":seeded_value was deleted from the :trogon_test application environment for this test",
                   fn -> Mock.fetch_env!(:trogon_test, :seeded_value) end
    end

    test "is undone by put_env/3" do
      TestApplication.delete_env(:trogon_test, :seeded_value)
      TestApplication.put_env(:trogon_test, :seeded_value, "back")

      value = Mock.get_env(:trogon_test, :seeded_value)

      assert value == "back"
    end
  end

  describe "get_all_env/1" do
    test "applies overrides on top of the real env" do
      TestApplication.put_env(:trogon_test, :seeded_value, "overridden")
      TestApplication.put_env(:trogon_test, :extra, :added)

      env = Mock.get_all_env(:trogon_test)

      assert Enum.sort(env) == [extra: :added, seeded_list: [a: 1, b: 2], seeded_value: "overridden"]
    end
  end

  describe "process ownership" do
    test "reaches the test's $callers" do
      TestApplication.put_env(:trogon_test, :seeded_value, "overridden")

      value = Task.await(Task.async(fn -> Mock.get_env(:trogon_test, :seeded_value) end))

      assert value == "overridden"
    end

    test "reaches a process allowed with Mox.allow/3" do
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
end

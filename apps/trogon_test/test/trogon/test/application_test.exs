defmodule Trogon.Test.ApplicationTest do
  use ExUnit.Case, async: true

  alias Trogon.Test.Application, as: TestApplication
  alias Trogon.Test.Support.EchoServer

  doctest Trogon.Test.Application

  test "falls through to the real Application env when there is no override" do
    assert TestApplication.get_env(:trogon_test, :seeded_value) == "real value"
    assert TestApplication.get_env(:trogon_test, :does_not_exist) == nil
    assert TestApplication.get_env(:trogon_test, :does_not_exist, :default) == :default
  end

  describe "put_env/3" do
    test "replaces the effective value for the calling process alone" do
      assert TestApplication.put_env(:trogon_test, :seeded_value, "overridden") == :ok
      assert TestApplication.get_env(:trogon_test, :seeded_value) == "overridden"
    end

    test "stacks: the latest call wins" do
      TestApplication.put_env(:trogon_test, :seeded_value, "first")
      TestApplication.put_env(:trogon_test, :seeded_value, "second")

      assert TestApplication.get_env(:trogon_test, :seeded_value) == "second"
    end
  end

  describe "merge_env/3" do
    test "deep merges onto the current effective value" do
      assert TestApplication.merge_env(:trogon_test, :seeded_list, c: 3) == :ok
      assert TestApplication.get_env(:trogon_test, :seeded_list) == [a: 1, b: 2, c: 3]
    end

    test "deep merges nested keyword lists key by key" do
      TestApplication.put_env(:trogon_test, :nested, outer: [inner: [x: 1, y: 2]])
      TestApplication.merge_env(:trogon_test, :nested, outer: [inner: [y: :changed, z: 3]])

      assert TestApplication.get_env(:trogon_test, :nested) == [outer: [inner: [x: 1, y: :changed, z: 3]]]
    end

    test "replaces a non-keyword value outright" do
      TestApplication.put_env(:trogon_test, :scalar, 1)
      TestApplication.merge_env(:trogon_test, :scalar, 2)

      assert TestApplication.get_env(:trogon_test, :scalar) == 2
    end

    test "merges onto no current value the same as put_env" do
      assert TestApplication.merge_env(:trogon_test, :brand_new, a: 1) == :ok
      assert TestApplication.get_env(:trogon_test, :brand_new) == [a: 1]
    end

    test "stacks: each merge builds on the previous one" do
      TestApplication.merge_env(:trogon_test, :seeded_list, c: 3)
      TestApplication.merge_env(:trogon_test, :seeded_list, d: 4)

      assert TestApplication.get_env(:trogon_test, :seeded_list) == [a: 1, b: 2, c: 3, d: 4]
    end
  end

  describe "delete_env/2" do
    test "the key reads as missing" do
      assert TestApplication.delete_env(:trogon_test, :seeded_value) == :ok
      assert TestApplication.get_env(:trogon_test, :seeded_value) == nil
      assert TestApplication.get_env(:trogon_test, :seeded_value, :default) == :default
    end

    test "a merge_env after a delete_env merges onto nothing" do
      TestApplication.delete_env(:trogon_test, :seeded_list)
      TestApplication.merge_env(:trogon_test, :seeded_list, c: 3)

      assert TestApplication.get_env(:trogon_test, :seeded_list) == [c: 3]
    end

    test "a put_env after a delete_env is visible again" do
      TestApplication.delete_env(:trogon_test, :seeded_value)
      TestApplication.put_env(:trogon_test, :seeded_value, "back")

      assert TestApplication.get_env(:trogon_test, :seeded_value) == "back"
    end
  end

  describe "fetch_env/2 and fetch_env!/2" do
    test "fetch_env/2 falls through to the real Application env" do
      assert TestApplication.fetch_env(:trogon_test, :seeded_value) == {:ok, "real value"}
    end

    test "fetch_env/2 returns the overridden value" do
      TestApplication.put_env(:trogon_test, :seeded_value, "overridden")
      assert TestApplication.fetch_env(:trogon_test, :seeded_value) == {:ok, "overridden"}
    end

    test "fetch_env/2 returns :error once the key is deleted" do
      TestApplication.delete_env(:trogon_test, :seeded_value)
      assert TestApplication.fetch_env(:trogon_test, :seeded_value) == :error
    end

    test "fetch_env!/2 returns the value when present" do
      assert TestApplication.fetch_env!(:trogon_test, :seeded_value) == "real value"
    end

    test "fetch_env!/2 raises when the key is missing but the application is loaded" do
      assert_raise ArgumentError, ~r/was not set/, fn ->
        TestApplication.fetch_env!(:trogon_test, :does_not_exist)
      end
    end

    test "fetch_env!/2 raises when the key was deleted for this test" do
      TestApplication.delete_env(:trogon_test, :seeded_value)

      assert_raise ArgumentError, ~r/was not set/, fn ->
        TestApplication.fetch_env!(:trogon_test, :seeded_value)
      end
    end

    test "fetch_env!/2 raises when the application itself was never loaded" do
      assert_raise ArgumentError, ~r/was not loaded nor configured/, fn ->
        TestApplication.fetch_env!(:an_application_that_does_not_exist, :key)
      end
    end
  end

  describe "get_all_env/1" do
    test "returns the real environment when there is no override" do
      env = TestApplication.get_all_env(:trogon_test)

      assert env[:seeded_value] == "real value"
      assert env[:seeded_list] == [a: 1, b: 2]
    end

    test "applies put_env, merge_env, and delete_env on top of the real environment" do
      TestApplication.put_env(:trogon_test, :added_key, "added")
      TestApplication.merge_env(:trogon_test, :seeded_list, c: 3)
      TestApplication.delete_env(:trogon_test, :seeded_value)

      env = TestApplication.get_all_env(:trogon_test)

      assert env[:added_key] == "added"
      assert env[:seeded_list] == [a: 1, b: 2, c: 3]
      refute Keyword.has_key?(env, :seeded_value)
    end
  end

  test "an override is invisible to an unrelated process" do
    TestApplication.put_env(:trogon_test, :seeded_value, "owned by this test")
    parent = self()

    spawn(fn ->
      send(parent, {:unrelated, TestApplication.get_env(:trogon_test, :seeded_value)})
    end)

    assert_receive {:unrelated, "real value"}
  end

  test "an override is visible to $callers, such as a Task" do
    TestApplication.put_env(:trogon_test, :seeded_value, "owned by the test")

    task = Task.async(fn -> TestApplication.get_env(:trogon_test, :seeded_value) end)

    assert Task.await(task) == "owned by the test"
  end

  test "allow/2 lets a process outside of $callers read the owner's overrides" do
    TestApplication.put_env(:trogon_test, :seeded_value, "owned by the test")
    {:ok, server} = EchoServer.start_link()

    assert EchoServer.get_env(server, :trogon_test, :seeded_value) == "real value"

    assert TestApplication.allow(server) == :ok
    assert EchoServer.get_env(server, :trogon_test, :seeded_value) == "owned by the test"
  end

  test "a write from a $caller lands in the owner's overrides" do
    Task.await(Task.async(fn -> TestApplication.put_env(:trogon_test, :seeded_value, "from the task") end))

    assert TestApplication.get_env(:trogon_test, :seeded_value) == "from the task"
  end

  test "a write from an allowed process lands in the owner's overrides" do
    TestApplication.put_env(:trogon_test, :seeded_value, "owned by the test")
    parent = self()

    pid =
      spawn(fn ->
        receive do
          :write ->
            TestApplication.put_env(:trogon_test, :seeded_value, "from the allowed process")
            send(parent, :written)
        end
      end)

    TestApplication.allow(pid)
    send(pid, :write)
    assert_receive :written

    assert TestApplication.get_env(:trogon_test, :seeded_value) == "from the allowed process"
  end

  test "overrides disappear once the owner exits, with no cleanup from the test" do
    parent = self()

    {child, ref} =
      spawn_monitor(fn ->
        TestApplication.put_env(:trogon_test, :seeded_value, "owned by a child process")
        TestApplication.allow(parent)
        send(parent, :ready)

        receive do
          :exit -> :ok
        end
      end)

    assert_receive :ready
    assert TestApplication.get_env(:trogon_test, :seeded_value) == "owned by a child process"

    send(child, :exit)
    assert_receive {:DOWN, ^ref, :process, ^child, :normal}

    assert TestApplication.get_env(:trogon_test, :seeded_value) == "real value"
  end
end

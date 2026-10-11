if Code.ensure_loaded?(Uniq.UUID) do
  defmodule Trogon.Test.TestUUID do
    @moduledoc """
    Helpers for `Trogon.Test.MockUUID`, the Mox mock of `Uniq.UUID`, that expect
    a generated UUID and assert on what it was given.

    Available when the project depends on `:uniq`.

    Code that calls `Uniq.UUID.uuid4/1` or `Uniq.UUID.uuid7/1` directly
    generates a different UUID on every run, so a test cannot assert on the
    identifiers it stores or sends. Generate them through a facade the project
    compiles in, `Uniq.UUID` in every environment but test:

        defmodule MyApp do
          @uuid Application.compile_env(:my_app, [__MODULE__, :uuid], Uniq.UUID)

          defdelegate uuid4(format \\\\ :default), to: @uuid
          defdelegate uuid7(format \\\\ :default), to: @uuid
        end

    and in `config/test.exs`:

        config :my_app, MyApp, uuid: Trogon.Test.MockUUID

    The mock has `uuid4/1` and `uuid7/1` and no `/0`, so the facade always passes
    a format, as the one above does through its default argument.

    `use Trogon.Test` stubs the mock to generate real UUIDs. Each test expects
    the UUIDs it cares about with what they return, and asserts on what they
    were given:

        use Trogon.Test

        test "stores the order under a new id" do
          TestUUID.expect_uuid7(times: 1, returns: "01a128c8-383e-7f3b-8f53-5fa308ac0d07")

          assert {:ok, order} = MyApp.Orders.place()

          assert order.id == "01a128c8-383e-7f3b-8f53-5fa308ac0d07"
          TestUUID.assert_received_uuid7()
          Trogon.Test.assert_empty_mailbox()
        end

    Every `expect_*` function takes:

      * `:returns` - the UUID every expected call returns. Required. It must be a
        UUID of the version the function generates, and a call asking for
        another format raises `ArgumentError`, since `Uniq.UUID` only returns
        the format it is given.
      * `:times` - how many calls the expectation covers. Defaults to `1`.

    A call past `:times` raises `Mox.UnexpectedCallError`. Each expected call is
    recorded in the mailbox of the test that set it, for the matching
    `assert_received_*` macro.

    The expectations reach the test's `$callers`, such as a `Task`, and a
    process allowed with `Trogon.Test.allow/1`.

    `uuid5/1` names a fixture without a mock: the same name gives the same UUID
    on every run, so a test can build an id, and assert on it, from a readable
    seed.
    """

    alias Trogon.Test.Expectation
    alias Trogon.Test.MockUUID
    alias Trogon.Test.Recorder

    @formats [:default, :raw, :hex, :urn, :slug]
    @namespace Uniq.UUID.uuid5(:url, "https://hex.pm/packages/trogon_test")

    @typedoc "Options every `expect_*` function takes."
    @type expect_opts :: [returns: Uniq.UUID.formatted(), times: non_neg_integer()]

    @doc """
    Stubs `Trogon.Test.MockUUID` to generate real UUIDs.

    Takes the test context so it can be given to `setup/1` as
    `setup {Trogon.Test.TestUUID, :stub}`.
    """
    @spec stub(map()) :: :ok
    def stub(_context \\ %{}) do
      Mox.stub_with(MockUUID, __MODULE__.UniqUUID)
      :ok
    end

    @doc """
    Expects `uuid4/1` on the mock, returning `opts[:returns]`.
    """
    @spec expect_uuid4(expect_opts()) :: module()
    def expect_uuid4(opts), do: expect_uuid(:uuid4, 4, opts)

    @doc """
    Expects `uuid7/1` on the mock, returning `opts[:returns]`.
    """
    @spec expect_uuid7(expect_opts()) :: module()
    def expect_uuid7(opts), do: expect_uuid(:uuid7, 7, opts)

    @doc """
    Returns the version 5 UUID of `name`, the same one on every run.

        TestUUID.uuid5("seller-456")
        #=> "853d34f8-13b3-5761-a4b2-2018ea01306e"

    The namespace is the version 5 UUID of the `trogon_test` package URL, so the
    UUIDs stay apart from any other namespace generates.
    """
    @spec uuid5(String.t()) :: Uniq.UUID.formatted()
    def uuid5(name) when is_binary(name), do: Uniq.UUID.uuid5(@namespace, name)

    @doc """
    Asserts an expected `uuid4/1` call was made, whatever format it asked for.
    """
    defmacro assert_received_uuid4 do
      quote do
        Recorder.asserted(ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestUUID, {:uuid4, [_format]}}}))
      end
    end

    @doc """
    Asserts an expected `uuid4/1` call asked for `format`.
    """
    defmacro assert_received_uuid4(format) do
      quote bind_quoted: [format: format] do
        Recorder.asserted(ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestUUID, {:uuid4, [^format]}}}))
      end
    end

    @doc """
    Asserts an expected `uuid7/1` call was made, whatever format it asked for.
    """
    defmacro assert_received_uuid7 do
      quote do
        Recorder.asserted(ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestUUID, {:uuid7, [_format]}}}))
      end
    end

    @doc """
    Asserts an expected `uuid7/1` call asked for `format`.
    """
    defmacro assert_received_uuid7(format) do
      quote bind_quoted: [format: format] do
        Recorder.asserted(ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestUUID, {:uuid7, [^format]}}}))
      end
    end

    defp expect_uuid(function, version, opts) do
      recorder = Recorder.new()
      uuid = Expectation.returns!(opts, &uuid_version?(&1, version), "a version #{version} UUID")
      {:ok, %{format: uuid_format}} = Uniq.UUID.info(uuid)

      Mox.expect(MockUUID, function, Expectation.times(opts), fn format when format in @formats ->
        if format != uuid_format do
          raise ArgumentError,
                "expected :returns to be in the #{inspect(format)} format #{function}/1 was given, got: #{inspect(uuid)}"
        end

        Expectation.record(recorder, __MODULE__, {function, [format]}, uuid)
      end)
    end

    defp uuid_version?(value, version) do
      match?({:ok, %{version: ^version}}, Uniq.UUID.info(value))
    end
  end
end

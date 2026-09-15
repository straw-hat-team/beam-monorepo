defmodule Trogon.DispatcherTest do
  use ExUnit.Case, async: true

  import Trogon.Dispatcher.Test

  alias Trogon.Dispatcher.Context
  alias Trogon.Dispatcher.DispatchError
  alias Trogon.Dispatcher.DispatchOptions
  alias Trogon.Dispatcher.InvalidContextError
  alias Trogon.Dispatcher.InvalidResponseError
  alias Trogon.Dispatcher.TestSupport, as: Support
  alias Trogon.Dispatcher.UnregisteredMessageError

  describe "dispatch_message/2" do
    test "routes to the message module itself by default" do
      assert {:ok, %Support.User{email: "a@b.c"}} =
               Support.AccountsDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"})
    end

    test "routes to the handler named by :to" do
      assert :ok = Support.AccountsDispatcher.dispatch_message(%Support.ArchiveUser{id: 1})
    end

    test "dispatches a query the same way as a message" do
      assert {:ok, %Support.User{email: "read@example.com"}} =
               Support.AccountsDispatcher.dispatch_message(%Support.GetUser{id: 1})
    end

    test "passes caller options through to the context" do
      options = %DispatchOptions{actor: :someone, assigns: %{trail: []}}

      assert {:ok, %Support.User{actor: :someone}} =
               Support.AccountsDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)
    end

    test "returns the handler's error term untouched" do
      assert {:error, :nope} = Support.AccountsDispatcher.dispatch_message(%Support.FailingCommand{})
    end

    test "returns an unregistered message as a value, not a raise" do
      assert {:error, %UnregisteredMessageError{} = error} =
               Support.AccountsDispatcher.dispatch_message(%Support.NotRegistered{})

      assert error.dispatched_message == %Support.NotRegistered{}
      assert error.dispatcher == Support.AccountsDispatcher
      assert Exception.message(error) =~ "Unregistered message Trogon.Dispatcher.TestSupport.NotRegistered"
    end

    test "raises when the message argument is not a struct" do
      assert_raise ArgumentError, ~r/expected a struct as the first argument, got: :not_a_struct/, fn ->
        Support.AccountsDispatcher.dispatch_message(:not_a_struct)
      end
    end

    test "raises when the options argument is not a DispatchOptions" do
      assert_raise ArgumentError, ~r/expected a %Trogon.Dispatcher.DispatchOptions\{\}/, fn ->
        Support.AccountsDispatcher.dispatch_message(%Support.RegisterUser{}, actor: :someone)
      end
    end

    test "lets handler exceptions through untouched" do
      assert_raise RuntimeError, "boom", fn ->
        Support.AccountsDispatcher.dispatch_message(%Support.ExplodingCommand{})
      end
    end
  end

  describe "response contract" do
    test "rejects a bare list as the success value" do
      error =
        assert_raise InvalidResponseError, fn ->
          Support.AccountsDispatcher.dispatch_message(%Support.ListReturningCommand{})
        end

      assert error.module == Support.ListReturningCommand
      assert error.dispatcher == Support.AccountsDispatcher
      assert Exception.message(error) =~ "The success value must be a struct"
    end

    test "rejects a map as the success value" do
      assert_raise InvalidResponseError, fn ->
        Support.AccountsDispatcher.dispatch_message(%Support.MapReturningCommand{})
      end
    end

    test "requires a middleware to return a context and names the offending middleware" do
      error =
        assert_raise InvalidContextError, fn ->
          Support.BadMiddlewareDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"})
        end

      assert error.module == Support.BadMiddleware
      assert error.dispatcher == Support.BadMiddlewareDispatcher
      assert Exception.message(error) =~ "Expected: a %Trogon.Dispatcher.Context{}"
    end

    test "rejects a middleware that halts without putting a response" do
      error =
        assert_raise InvalidResponseError, fn ->
          Support.HaltingDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"})
        end

      assert error.module == Support.Halting
      assert Exception.message(error) =~ "must put its own response on the context"
    end
  end

  describe "backward pipe" do
    test "the stop metadata carries the context the pipeline finished with" do
      attach_telemetry!()

      assert {:ok, _user} = Support.StampDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"})

      metadata = assert_dispatch_stop(Support.RegisterUser)

      assert metadata.context.private[Support.Stamp] == :stamped
      assert metadata.context.private[Support.RequireTenant] == "acme"
      assert metadata.context.assigns.trail == [:require_tenant, :stamp]
      assert {:ok, %Support.User{}} = metadata.context.response
    end
  end

  describe "dispatch_message!/2" do
    test "unwraps a success value" do
      assert %Support.User{email: "a@b.c"} =
               Support.AccountsDispatcher.dispatch_message!(%Support.RegisterUser{email: "a@b.c"})
    end

    test "passes :ok through" do
      assert :ok = Support.AccountsDispatcher.dispatch_message!(%Support.ArchiveUser{id: 1})
    end

    test "wraps a non-exception error term in DispatchError" do
      error =
        assert_raise DispatchError, fn ->
          Support.AccountsDispatcher.dispatch_message!(%Support.FailingCommand{})
        end

      assert error.reason == :nope
      assert error.dispatcher == Support.AccountsDispatcher
      assert Exception.message(error) =~ "failed with :nope"
    end

    test "re-raises an exception error term as itself" do
      assert_raise UnregisteredMessageError, fn ->
        Support.AccountsDispatcher.dispatch_message!(%Support.NotRegistered{})
      end
    end
  end

  describe "middleware composition" do
    test "the importer's middleware wraps the imported dispatcher's" do
      options = %DispatchOptions{assigns: %{trail: []}}

      assert {:ok, %Support.User{trail: [:authorize, :require_tenant]}} =
               Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)
    end

    test "imported middleware stays attached to its own registrations" do
      options = %DispatchOptions{assigns: %{trail: []}}

      assert {:ok, %Support.User{trail: [:authorize]}} =
               Support.RootDispatcher.dispatch_message(%Support.BillingCommand{}, options)
    end

    test "a leaf dispatcher is a first-class entry point and runs only its own middleware" do
      options = %DispatchOptions{assigns: %{trail: []}}

      assert {:ok, %Support.User{trail: [:require_tenant]}} =
               Support.AccountsDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)
    end

    test "not calling next halts the pipeline" do
      options = %DispatchOptions{actor: :forbidden}

      assert {:error, :unauthorized} =
               Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)
    end

    test "init/1 runs at compile time and its result reaches call/3" do
      assert {:ok, %Support.User{tenant: "acme"}} =
               Support.AccountsDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"})
    end

    test "a middleware without init/1 receives its options unchanged" do
      options = %DispatchOptions{assigns: %{trail: []}}

      assert {:ok, %Support.User{trail: [{:no_init, [some: :option]}]}} =
               Support.NoInitDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)
    end
  end

  describe "import composition" do
    test "a diamond dedupes instead of conflicting" do
      assert {:ok, %Support.User{}} = Support.DiamondDispatcher.dispatch_message(%Support.BillingCommand{})
    end

    test "registrations carry the dispatcher that registered them" do
      registrations = Support.RootDispatcher.__trogon_dispatcher__(:registrations)
      registration = Enum.find(registrations, &(&1.message == Support.RegisterUser))

      assert registration.registered_by == Support.AccountsDispatcher
      assert registration.kind == :command
      assert registration.handler == Support.RegisterUser
      assert Enum.map(registration.middleware, &elem(&1, 0)) == [Support.Authorize, Support.RequireTenant]
    end

    test "exposes its own middleware and direct imports" do
      assert [{Support.Authorize, []}] = Support.RootDispatcher.__trogon_dispatcher__(:middleware)

      assert [Support.AccountsDispatcher, Support.BillingDispatcher] =
               Support.RootDispatcher.__trogon_dispatcher__(:imports)
    end

    test "exposes its telemetry prefix" do
      assert [:support, :root] = Support.RootDispatcher.__trogon_dispatcher__(:telemetry_prefix)
      assert [:trogon_dispatcher] = Support.AccountsDispatcher.__trogon_dispatcher__(:telemetry_prefix)
    end
  end

  describe "context" do
    test "carries the dispatcher and the registering dispatcher separately" do
      options = %DispatchOptions{assigns: %{trail: []}}

      attach_telemetry!([:support, :root])
      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)

      metadata = assert_dispatch_stop(Support.RegisterUser)

      assert metadata.context.dispatcher == Support.RootDispatcher
      assert metadata.context.registered_by == Support.AccountsDispatcher
    end

    test "assign/3 writes host space and put_private/3 writes middleware space" do
      context = build_context(%Support.RegisterUser{})

      context = Context.assign(context, :thing, 1)
      context = Context.put_private(context, Support.RequireTenant, "tenant")

      assert context.assigns == %{thing: 1}
      assert Context.get_private(context, Support.RequireTenant) == "tenant"
      assert Context.get_private(context, Unknown, :default) == :default
    end
  end

  describe "DispatchOptions.from_context/1" do
    test "carries correlation and actor forward but not causation" do
      context =
        build_context(%Support.RegisterUser{}, %DispatchOptions{
          correlation_id: "corr",
          causation_id: "cause",
          actor: :someone,
          assigns: %{thing: 1}
        })

      assert %DispatchOptions{
               correlation_id: "corr",
               causation_id: nil,
               actor: :someone,
               assigns: %{thing: 1}
             } = DispatchOptions.from_context(context)
    end
  end
end

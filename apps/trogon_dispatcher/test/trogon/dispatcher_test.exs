defmodule Trogon.DispatcherTest do
  use ExUnit.Case, async: true

  alias Trogon.Dispatcher.Context
  alias Trogon.Dispatcher.DispatchError
  alias Trogon.Dispatcher.DispatchOptions
  alias Trogon.Dispatcher.InvalidContextError
  alias Trogon.Dispatcher.InvalidResponseError
  alias Trogon.Dispatcher.TestSupport, as: Support
  alias Trogon.Dispatcher.UnregisteredMessageError

  require Trogon.Dispatcher.Test, as: Test

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
      options = DispatchOptions.new!(actor: :someone, assigns: %{trail: []})

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
      Test.attach_telemetry!()

      assert {:ok, _user} = Support.StampDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"})

      metadata = Test.assert_dispatch_stop(Support.RegisterUser)

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
      options = DispatchOptions.new!(assigns: %{trail: []})

      assert {:ok, %Support.User{trail: [:authorize, :require_tenant]}} =
               Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)
    end

    test "imported middleware stays attached to its own registrations" do
      options = DispatchOptions.new!(assigns: %{trail: []})

      assert {:ok, %Support.User{trail: [:authorize]}} =
               Support.RootDispatcher.dispatch_message(%Support.BillingCommand{}, options)
    end

    test "a leaf dispatcher is a first-class entry point and runs only its own middleware" do
      options = DispatchOptions.new!(assigns: %{trail: []})

      assert {:ok, %Support.User{trail: [:require_tenant]}} =
               Support.AccountsDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)
    end

    test "not calling next halts the pipeline" do
      options = DispatchOptions.new!(actor: :forbidden)

      assert {:error, :unauthorized} =
               Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)
    end

    test "init/1 runs at compile time and its result reaches call/3" do
      assert {:ok, %Support.User{tenant: "acme"}} =
               Support.AccountsDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"})
    end

    test "a middleware without init/1 receives its options unchanged" do
      options = DispatchOptions.new!(assigns: %{trail: []})

      assert {:ok, %Support.User{trail: [{:no_init, [some: :option]}]}} =
               Support.NoInitDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)
    end

    test "bakes the struct init/1 returned into the pipeline unchanged" do
      assert [{Support.RequireTenant, %Support.RequireTenant.Options{tenant: "acme"}}] =
               Support.AccountsDispatcher.__trogon_dispatcher__(:middleware)
    end
  end

  describe "import composition" do
    test "a diamond dedupes instead of conflicting" do
      assert {:ok, %Support.User{}} = Support.DiamondDispatcher.dispatch_message(%Support.BillingCommand{})

      registrations = Support.DiamondDispatcher.__trogon_dispatcher__(:registrations)

      assert [_registration] = Enum.filter(registrations, &(&1.message == Support.BillingCommand))
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
      assert [{Support.Authorize, %Support.Authorize.Options{}}] =
               Support.RootDispatcher.__trogon_dispatcher__(:middleware)

      assert [Support.AccountsDispatcher, Support.BillingDispatcher] =
               Support.RootDispatcher.__trogon_dispatcher__(:imports)
    end
  end

  describe "context" do
    test "carries the dispatcher and the registering dispatcher separately" do
      options = DispatchOptions.new!(assigns: %{trail: []})

      Test.attach_telemetry!()
      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)

      metadata = Test.assert_dispatch_stop(Support.RegisterUser)

      assert metadata.context.dispatcher == Support.RootDispatcher
      assert metadata.context.registered_by == Support.AccountsDispatcher
    end

    test "Context.new/1 builds a command context with no dispatcher and empty options" do
      assert %Context{
               message: %Support.RegisterUser{email: "a@b.c"},
               kind: :command,
               dispatcher: nil,
               registered_by: nil,
               message_id: nil,
               correlation_id: nil,
               causation_id: nil,
               actor: nil,
               assigns: %{},
               private: %{},
               response: nil
             } = Context.new(%Support.RegisterUser{email: "a@b.c"})
    end

    test "Context.new/3 defaults registered_by to the dispatcher" do
      context =
        Context.new(%Support.GetUser{id: 1}, DispatchOptions.new!(), kind: :query, dispatcher: Support.RootDispatcher)

      assert context.kind == :query
      assert context.dispatcher == Support.RootDispatcher
      assert context.registered_by == Support.RootDispatcher
    end

    test "assign/3 writes host space and put_private/3 writes middleware space" do
      context = Test.build_context(%Support.RegisterUser{})

      context = Context.assign(context, :thing, 1)
      context = Context.put_private(context, Support.RequireTenant, "tenant")

      assert context.assigns == %{thing: 1}
      assert Context.get_private(context, Support.RequireTenant) == "tenant"
      assert Context.get_private(context, Unknown, :default) == :default
    end
  end

  describe "Context.to_dispatch_options/1" do
    test "carries correlation and actor forward, sets causation to the current message_id, and drops message_id" do
      context =
        Test.build_context(
          %Support.RegisterUser{},
          DispatchOptions.new!(
            message_id: "msg-1",
            correlation_id: "corr",
            causation_id: "cause",
            actor: :someone,
            assigns: %{thing: 1}
          )
        )

      assert %DispatchOptions{
               message_id: nil,
               correlation_id: "corr",
               causation_id: "msg-1",
               actor: :someone,
               assigns: %{thing: 1}
             } = Context.to_dispatch_options(context)
    end
  end
end

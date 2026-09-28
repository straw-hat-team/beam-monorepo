defmodule Trogon.Dispatcher.TestTest do
  use ExUnit.Case, async: true

  alias Trogon.Dispatcher.Context
  alias Trogon.Dispatcher.DispatchOptions
  alias Trogon.Dispatcher.Test
  alias Trogon.Dispatcher.TestSupport, as: Support

  require Test

  setup {Mox, :verify_on_exit!}

  describe "build_context/3" do
    test "builds a context without going through a dispatcher" do
      context = Test.build_context(%Support.RegisterUser{email: "a@b.c"})

      assert %Context{} = context
      assert context.message == %Support.RegisterUser{email: "a@b.c"}
      assert context.kind == :command
      assert context.assigns == %{}
      assert context.private == %{}
    end

    test "carries the dispatch options" do
      options = %DispatchOptions{
        message_id: "msg-1",
        correlation_id: "corr-1",
        causation_id: "cause-1",
        actor: :root,
        assigns: %{locale: "en"}
      }

      context = Test.build_context(%Support.GetUser{id: 1}, options, kind: :query)

      assert context.kind == :query
      assert context.message_id == "msg-1"
      assert context.correlation_id == "corr-1"
      assert context.causation_id == "cause-1"
      assert context.actor == :root
      assert context.assigns == %{locale: "en"}
    end

    test "accepts overrides for the attribution fields" do
      context =
        Test.build_context(%Support.RegisterUser{}, %DispatchOptions{},
          dispatcher: Support.RootDispatcher,
          registered_by: Support.AccountsDispatcher,
          private: %{seeded: true}
        )

      assert context.dispatcher == Support.RootDispatcher
      assert context.registered_by == Support.AccountsDispatcher
      assert context.private == %{seeded: true}
    end
  end

  describe "call_handler/2" do
    test "hands the handler the context's message and returns its response" do
      context = Test.build_context(%Support.RegisterUser{email: "a@b.c"}, %DispatchOptions{actor: :alice})

      assert {:ok, %Support.User{email: "a@b.c", actor: :alice}} = Test.call_handler(Support.RegisterUser, context)
    end

    test "passes an error response through" do
      context = Test.build_context(%Support.FailingCommand{})

      assert {:error, _reason} = Test.call_handler(Support.FailingCommand, context)
    end

    test "raises when the success value is not a struct" do
      context = Test.build_context(%Support.MapReturningCommand{})

      assert_raise Trogon.Dispatcher.InvalidResponseError, fn ->
        Test.call_handler(Support.MapReturningCommand, context)
      end
    end
  end

  describe "call_middleware/3" do
    test "runs init/1 before call/3" do
      context = Test.build_context(%Support.RegisterUser{})

      reached = Test.call_middleware(Support.RequireTenant, context, options: [tenant: "globex"])

      assert reached.private[Support.RequireTenant] == "globex"
      assert reached.response == :ok
    end

    test "passes the context through to next" do
      context = Test.build_context(%Support.RegisterUser{})

      reached = Test.call_middleware(Support.RequireTenant, context)

      assert reached.private[Support.RequireTenant] == "acme"
      assert reached.assigns.trail == [:require_tenant]
    end

    test "a halting middleware never reaches next" do
      context = Test.build_context(%Support.RegisterUser{}, %DispatchOptions{actor: :forbidden})

      halted =
        Test.call_middleware(Support.Authorize, context,
          next: fn _ctx ->
            flunk("next should not have been called")
          end
        )

      assert halted.response == {:error, :unauthorized}
    end

    test "a middleware without init/1 receives the raw options" do
      context = Test.build_context(%Support.RegisterUser{})

      reached = Test.call_middleware(Support.NoInit, context, options: [some: :option])

      assert reached.assigns.trail == [{:no_init, [some: :option]}]
    end

    test "raises when init/1 does not return a struct" do
      context = Test.build_context(%Support.RegisterUser{})

      assert_raise ArgumentError, ~r/to return a struct/, fn ->
        Test.call_middleware(Support.NonStructInit, context)
      end
    end

    test "returns the context an inner next handed back" do
      context = Test.build_context(%Support.RegisterUser{})

      reached =
        Test.call_middleware(Support.Stamp, context,
          next: fn ctx ->
            ctx |> Context.assign(:inner, true) |> Context.put_response(:ok)
          end
        )

      assert reached.assigns.inner == true
      assert reached.private[Support.Stamp] == :stamped
      assert reached.response == :ok
    end

    test "raises when the middleware does not return a context" do
      context = Test.build_context(%Support.RegisterUser{})

      assert_raise Trogon.Dispatcher.InvalidContextError, fn ->
        Test.call_middleware(Support.BadMiddleware, context)
      end
    end

    test "raises when the middleware halts without a response" do
      context = Test.build_context(%Support.RegisterUser{})

      assert_raise Trogon.Dispatcher.InvalidResponseError, fn ->
        Test.call_middleware(Support.Halting, context)
      end
    end
  end

  describe "attach_telemetry!/0" do
    test "forwards the dispatch events" do
      Test.attach_telemetry!()

      assert {:ok, _user} = Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"})

      Test.assert_dispatch_start(Support.RegisterUser)
      metadata = Test.assert_dispatch_stop(Support.RegisterUser)

      assert metadata.result == :ok
      assert metadata.registered_by == Support.AccountsDispatcher
    end

    test "detaches on exit so a later attach does not double up" do
      Test.attach_telemetry!()
      Test.attach_telemetry!()

      assert {:ok, _user} = Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"})

      Test.assert_dispatch_stop(Support.RegisterUser)
      Test.assert_dispatch_stop(Support.RegisterUser)
      refute_receive {Trogon.Dispatcher.Test, :stop, _event, _measurements, _metadata}
    end
  end

  describe "mocking a dispatcher with Mox" do
    test "a dispatcher is a behaviour, so Mox can mock it directly" do
      Mox.expect(Support.DispatcherMock, :dispatch_message, fn %Support.RegisterUser{} = message ->
        {:ok, %Support.User{email: message.email}}
      end)

      assert {:ok, %Support.User{email: "a@b.c"}} =
               Support.DispatcherMock.dispatch_message(%Support.RegisterUser{email: "a@b.c"})
    end

    test "the two-argument callback is mockable as well" do
      Mox.expect(Support.DispatcherMock, :dispatch_message, fn %Support.GetUser{}, %DispatchOptions{} = options ->
        send(self(), {:options, options})
        {:ok, %Support.User{email: "read@example.com"}}
      end)

      assert {:ok, _user} =
               Support.DispatcherMock.dispatch_message(%Support.GetUser{id: 1}, %DispatchOptions{actor: :root})

      assert_received {:options, %DispatchOptions{actor: :root}}
    end

    test "the bang callback is mockable" do
      Mox.expect(Support.DispatcherMock, :dispatch_message!, fn %Support.ArchiveUser{} -> :ok end)

      assert :ok = Support.DispatcherMock.dispatch_message!(%Support.ArchiveUser{id: 1})
    end
  end

  describe "expect_dispatch/3" do
    test "defaults the response to :ok" do
      Test.expect_dispatch(Support.DispatcherMock, Support.ArchiveUser)

      assert :ok = Support.DispatcherMock.dispatch_message(%Support.ArchiveUser{id: 1})
      Test.assert_dispatched(%Support.ArchiveUser{id: 1})
    end

    test "returns a plain response and records the options" do
      Test.expect_dispatch(Support.DispatcherMock, Support.RegisterUser, returns: {:ok, %Support.User{email: "a@b.c"}})

      assert {:ok, %Support.User{email: "a@b.c"}} =
               Support.DispatcherMock.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, %DispatchOptions{
                 actor: :alice
               })

      Test.assert_dispatched(%Support.RegisterUser{email: email}, %DispatchOptions{actor: :alice})
      assert email == "a@b.c"
    end

    test "builds the response from a function" do
      Test.expect_dispatch(Support.DispatcherMock, Support.RegisterUser,
        returns: fn %Support.RegisterUser{email: email}, %DispatchOptions{} -> {:ok, %Support.User{email: email}} end
      )

      assert {:ok, %Support.User{email: "a@b.c"}} =
               Support.DispatcherMock.dispatch_message(%Support.RegisterUser{email: "a@b.c"})
    end

    test "the bang variants unwrap the response like a real dispatcher" do
      Test.expect_dispatch(Support.DispatcherMock, Support.RegisterUser, returns: {:ok, %Support.User{email: "a@b.c"}})
      Test.expect_dispatch(Support.DispatcherMock, Support.ArchiveUser, returns: {:error, :gone})

      assert %Support.User{email: "a@b.c"} = Support.DispatcherMock.dispatch_message!(%Support.RegisterUser{})

      assert_raise Trogon.Dispatcher.DispatchError, fn ->
        Support.DispatcherMock.dispatch_message!(%Support.ArchiveUser{}, %DispatchOptions{})
      end
    end

    test "expects the given number of dispatches" do
      Test.expect_dispatch(Support.DispatcherMock, Support.ArchiveUser, times: 2)

      assert :ok = Support.DispatcherMock.dispatch_message(%Support.ArchiveUser{id: 1})
      assert :ok = Support.DispatcherMock.dispatch_message(%Support.ArchiveUser{id: 2})
      Test.assert_dispatched(%Support.ArchiveUser{id: 1})
      Test.assert_dispatched(%Support.ArchiveUser{id: 2})
    end

    test "raises when the mocked response breaks the contract" do
      Test.expect_dispatch(Support.DispatcherMock, Support.RegisterUser, returns: {:ok, %{email: "a@b.c"}})

      assert_raise Trogon.Dispatcher.InvalidResponseError, fn ->
        Support.DispatcherMock.dispatch_message(%Support.RegisterUser{})
      end
    end

    test "fails when a different message is dispatched" do
      Test.expect_dispatch(Support.DispatcherMock, Support.RegisterUser)

      assert_raise ExUnit.AssertionError, ~r/to dispatch #{inspect(Support.RegisterUser)}/, fn ->
        Support.DispatcherMock.dispatch_message(%Support.ArchiveUser{})
      end
    end
  end
end

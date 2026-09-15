defmodule Trogon.Dispatcher.TestTest do
  use ExUnit.Case, async: true

  import Mox
  import Trogon.Dispatcher.Test

  alias Trogon.Dispatcher.Context
  alias Trogon.Dispatcher.DispatchOptions
  alias Trogon.Dispatcher.Test
  alias Trogon.Dispatcher.TestSupport, as: Support

  setup :verify_on_exit!

  describe "build_context/3" do
    test "builds a context without going through a dispatcher" do
      context = Test.build_context(%Support.RegisterUser{email: "a@b.c"})

      assert %Context{} = context
      assert context.command == %Support.RegisterUser{email: "a@b.c"}
      assert context.kind == :command
      assert context.assigns == %{}
      assert context.private == %{}
    end

    test "carries the dispatch options" do
      options = %DispatchOptions{
        correlation_id: "corr-1",
        causation_id: "cause-1",
        actor: :root,
        assigns: %{locale: "en"}
      }

      context = Test.build_context(%Support.GetUser{id: 1}, options, kind: :query)

      assert context.kind == :query
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

  describe "call_middleware/4" do
    test "runs init/1 before call/3" do
      context = Test.build_context(%Support.RegisterUser{})

      reached = Test.call_middleware(Support.RequireTenant, [tenant: "globex"], context)

      assert reached.private[Support.RequireTenant] == "globex"
      assert reached.response == :ok
    end

    test "passes the context through to next" do
      context = Test.build_context(%Support.RegisterUser{})

      reached = Test.call_middleware(Support.RequireTenant, [], context)

      assert reached.private[Support.RequireTenant] == "acme"
      assert reached.assigns.trail == [:require_tenant]
    end

    test "a halting middleware never reaches next" do
      context = Test.build_context(%Support.RegisterUser{}, %DispatchOptions{actor: :forbidden})

      halted =
        Test.call_middleware(Support.Authorize, [], context, fn _ctx ->
          flunk("next should not have been called")
        end)

      assert halted.response == {:error, :unauthorized}
    end

    test "a middleware without init/1 receives the raw options" do
      context = Test.build_context(%Support.RegisterUser{})

      reached = Test.call_middleware(Support.NoInit, [some: :option], context)

      assert reached.assigns.trail == [{:no_init, [some: :option]}]
    end

    test "returns the context an inner next handed back" do
      context = Test.build_context(%Support.RegisterUser{})

      reached =
        Test.call_middleware(Support.Stamp, [], context, fn ctx ->
          ctx |> Context.assign(:inner, true) |> Context.put_response(:ok)
        end)

      assert reached.assigns.inner == true
      assert reached.private[Support.Stamp] == :stamped
      assert reached.response == :ok
    end
  end

  describe "attach_telemetry!/1" do
    test "forwards the events of the given prefix" do
      Test.attach_telemetry!([:support, :root])

      assert {:ok, _user} = Support.RootDispatcher.dispatch_command(%Support.RegisterUser{email: "a@b.c"})

      assert_dispatch_start(Support.RegisterUser)
      metadata = assert_dispatch_stop(Support.RegisterUser)

      assert metadata.result == :ok
      assert metadata.registered_by == Support.AccountsDispatcher
    end

    test "detaches on exit so a later attach does not double up" do
      Test.attach_telemetry!([:support, :root])
      Test.attach_telemetry!([:support, :root])

      assert {:ok, _user} = Support.RootDispatcher.dispatch_command(%Support.RegisterUser{email: "a@b.c"})

      assert_dispatch_stop(Support.RegisterUser)
      assert_dispatch_stop(Support.RegisterUser)
      refute_receive {:trogon_dispatcher_telemetry, :stop, _event, _measurements, _metadata}
    end
  end

  describe "mocking a dispatcher with Mox" do
    test "a dispatcher is a behaviour, so Mox can mock it directly" do
      expect(Support.DispatcherMock, :dispatch_command, fn %Support.RegisterUser{} = command ->
        {:ok, %Support.User{email: command.email}}
      end)

      assert {:ok, %Support.User{email: "a@b.c"}} =
               Support.DispatcherMock.dispatch_command(%Support.RegisterUser{email: "a@b.c"})
    end

    test "the two-argument callback is mockable as well" do
      expect(Support.DispatcherMock, :dispatch_command, fn %Support.GetUser{}, %DispatchOptions{} = options ->
        send(self(), {:options, options})
        {:ok, %Support.User{email: "read@example.com"}}
      end)

      assert {:ok, _user} =
               Support.DispatcherMock.dispatch_command(%Support.GetUser{id: 1}, %DispatchOptions{actor: :root})

      assert_received {:options, %DispatchOptions{actor: :root}}
    end

    test "the bang callback is mockable" do
      expect(Support.DispatcherMock, :dispatch_command!, fn %Support.ArchiveUser{} -> :ok end)

      assert :ok = Support.DispatcherMock.dispatch_command!(%Support.ArchiveUser{id: 1})
    end
  end
end

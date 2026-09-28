# Test with Mox

Every dispatcher is already a Mox-mockable behaviour; see the Generated API section of `Trogon.Dispatcher` for why.

## Define the mock

```elixir
# test/test_helper.exs
Mox.defmock(MyApp.DispatcherMock, for: MyApp.Dispatcher)

ExUnit.start()
```

## Inject the dispatcher

Read the dispatcher from config so tests can swap it:

```elixir
# config/test.exs
config :my_app, :dispatcher, MyApp.DispatcherMock
```

```elixir
defmodule MyAppWeb.UserController do
  @dispatcher Application.compile_env!(:my_app, :dispatcher)

  defdelegate dispatch_message(message, options), to: @dispatcher

  def create(conn, params) do
    case dispatch_message(%RegisterUser{email: params["email"]}, %DispatchOptions{}) do
      {:ok, user} -> render(conn, "show.json", user: user)
      {:error, reason} -> render_error(conn, reason)
    end
  end
end
```

## Set expectations

```elixir
defmodule MyAppWeb.UserControllerTest do
  use MyAppWeb.ConnCase, async: true

  import Mox
  import Trogon.Dispatcher.Test

  setup :verify_on_exit!

  test "creates a user", %{conn: conn} do
    expect_dispatch(MyApp.DispatcherMock, RegisterUser, returns: {:ok, %User{email: "a@b.c"}})

    conn = post(conn, ~p"/users", %{"email" => "a@b.c"})

    assert json_response(conn, 200)["email"] == "a@b.c"
    assert_dispatched(%RegisterUser{email: "a@b.c"})
  end
end
```

See `Trogon.Dispatcher.Test.expect_dispatch/3` for the options it takes and the contract it enforces, and
`Trogon.Dispatcher.Test` for why there is no per-message handler stubbing.

## Test the real dispatcher

For the dispatcher itself, do not mock anything. Dispatch is synchronous and in-process, so a plain call is the test:

```elixir
assert {:ok, %User{email: "a@b.c"}} = MyApp.Dispatcher.dispatch_message(%RegisterUser{email: "a@b.c"})
```

To exercise a handler or a middleware without a dispatcher at all, build a context directly:

```elixir
import Trogon.Dispatcher.Test

context = build_context(%RegisterUser{email: "a@b.c"}, %DispatchOptions{actor: actor}, kind: :command)

assert {:ok, %User{}} = call_handler(MyApp.Accounts.RegisterUser, context)
```

See `Trogon.Dispatcher.Test.build_context/3` for the overrides it accepts, and `Trogon.Dispatcher.Test.call_handler/2`
for the contract it enforces.

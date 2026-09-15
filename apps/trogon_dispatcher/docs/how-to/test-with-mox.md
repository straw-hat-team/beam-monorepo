# Test with Mox

Every dispatcher declares `dispatch_command/1`, `dispatch_command/2`, `dispatch_command!/1` and `dispatch_command!/2`
as callbacks on itself. A dispatcher is therefore already a behaviour, and Mox can mock it directly. There is no
companion `MyApp.Dispatcher.Behaviour` module and no generated `MyApp.Dispatcher.Mock`.

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
  defp dispatcher, do: Application.fetch_env!(:my_app, :dispatcher)

  def create(conn, params) do
    case dispatcher().dispatch_command(%RegisterUser{email: params["email"]}) do
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

  setup :verify_on_exit!

  test "creates a user", %{conn: conn} do
    expect(MyApp.DispatcherMock, :dispatch_command, fn %RegisterUser{email: email} ->
      {:ok, %User{email: email}}
    end)

    conn = post(conn, ~p"/users", %{"email" => "a@b.c"})

    assert json_response(conn, 200)["email"] == "a@b.c"
  end
end
```

Mock at the dispatcher boundary. There is deliberately no per-command handler stubbing: the dispatcher is the seam
your application code depends on, so it is the seam worth faking.

## Test the real dispatcher

For the dispatcher itself, do not mock anything. Dispatch is synchronous and in-process, so a plain call is the test:

```elixir
assert {:ok, %User{email: "a@b.c"}} = MyApp.Dispatcher.dispatch_command(%RegisterUser{email: "a@b.c"})
```

To exercise a handler or a middleware without a dispatcher at all, build a context directly:

```elixir
import Trogon.Dispatcher.Test

context = build_context(%RegisterUser{email: "a@b.c"}, %DispatchOptions{actor: actor}, kind: :command)

assert {:ok, %User{}} = MyApp.Accounts.RegisterUser.handle_command(context.command, context)
```

`build_context/3` accepts `:kind`, `:dispatcher`, `:registered_by` and `:private` as overrides.

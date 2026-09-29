defmodule Trogon.Dispatcher.Handler do
  @moduledoc """
  The behaviour a message handler implements.

  Implementing the behaviour is optional and buys you `@impl` checking. Exporting `handle_message/2` is not
  optional: every registered handler is checked after the dispatcher is verified, and a missing `handle_message/2`
  is a compile error.

  A handler defaults to the message module itself, so the common case needs no separate module:

      defmodule MyApp.Accounts.RegisterUser do
        @behaviour Trogon.Dispatcher.Handler

        defstruct [:email]

        @impl true
        def handle_message(%__MODULE__{} = message, _context) do
          {:ok, %MyApp.Accounts.User{email: message.email}}
        end
      end

  Use `to:` on `register_message` when the handler belongs somewhere else.

  ## Response contract

  `handle_message/2` returns one of exactly three shapes:

  | Response | Meaning |
  | --- | --- |
  | `:ok` | success with no value |
  | `{:ok, struct}` | success with a value, which must be a struct |
  | `{:error, term}` | failure, with any term as the reason |

  The success value must be a struct: a map, a keyword list, a bare list, a binary, an integer or `nil` is a
  contract violation, not a success. Wrap a collection in a struct you define. `{:error, term}` accepts any term;
  the library has no error type of its own. A command whose outcome is only the effect returns `:ok` rather than
  `{:ok, nil}`.

  A response outside these shapes raises `Trogon.Dispatcher.InvalidResponseError`, naming the handler, the message
  and the dispatcher. A middleware never returns a response directly either: it returns a
  `Trogon.Dispatcher.Context` whose `:response` field holds one of these same three shapes.
  """

  alias Trogon.Dispatcher.Context

  @type response :: :ok | {:ok, struct()} | {:error, term()}

  @callback handle_message(message :: struct(), context :: Context.t()) :: response()
end

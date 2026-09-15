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
  """

  alias Trogon.Dispatcher.Context

  @type response :: :ok | {:ok, struct()} | {:error, term()}

  @callback handle_message(message :: struct(), context :: Context.t()) :: response()
end

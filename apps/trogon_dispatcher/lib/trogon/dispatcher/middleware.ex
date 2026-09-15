defmodule Trogon.Dispatcher.Middleware do
  @moduledoc """
  The behaviour a middleware module implements.

  A middleware deals with exactly one data type: `Trogon.Dispatcher.Context`. It takes a context, it returns a
  context. The message and the response are fields on that context, never separate arguments and never separate
  return values.

  A middleware *wraps* the rest of the pipeline rather than reducing over it, so it can time the handler, open a span
  around it, rescue it, or retry it. `next` returning is the after-phase, `try/rescue` around `next` is failure
  handling, and not calling `next` is halting.

  Because the same type travels in both directions, anything a middleware learns is visible to the middleware that
  wrapped it, and anything an inner middleware assigns is visible on the way back out.

  ## Example

      defmodule MyApp.Authorize do
        @behaviour Trogon.Dispatcher.Middleware

        alias Trogon.Dispatcher.Context

        @impl true
        def init(opts), do: opts

        @impl true
        def call(%Context{} = context, next, _options) do
          if allowed?(context.actor, context.message) do
            context
            |> Context.assign(:authorized_at, DateTime.utc_now())
            |> next.()
            |> Context.put_private(__MODULE__, :checked)
          else
            Context.put_response(context, {:error, :unauthorized})
          end
        end
      end

  `init/1` runs once at compile time and its result is baked into the generated pipeline as the literal third
  argument to `call/3`, so it must return a term that can be represented in AST (no functions, pids, or references).
  It is optional; when a middleware does not export it the options reach `call/3` unchanged.

  Returning anything other than a `Trogon.Dispatcher.Context` raises `Trogon.Dispatcher.InvalidContextError` naming
  the middleware. The context's `response` is held to the response contract at the same boundary, so a middleware
  that halts without putting a response raises `Trogon.Dispatcher.InvalidResponseError`.
  """

  alias Trogon.Dispatcher.Context

  @type options :: term()
  @type next :: (Context.t() -> Context.t())

  @callback init(options()) :: options()
  @callback call(Context.t(), next(), options()) :: Context.t()

  @optional_callbacks init: 1
end

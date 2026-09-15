defmodule Trogon.Dispatcher.Context do
  @moduledoc """
  The value threaded through every middleware and handed to the handler.

  Reserved concepts (`correlation_id`, `causation_id`, `actor`) are first-class typed fields rather than entries in
  `private`, because host apps need to read them. `assigns` is host-app space and the library never reads it.
  `private` is middleware scratch space and should be namespaced by the owning module.

  The context is the only value a middleware sees. It travels forward into the pipeline and back out again, so a
  middleware reads and writes it on both legs and never touches the command or the response as separate arguments.

  `response` is empty on the way in and holds the handler's answer on the way out. A middleware halts by putting a
  response without calling `next`.
  """

  alias Trogon.Dispatcher.DispatchOptions

  @enforce_keys [:command, :kind, :dispatcher, :registered_by]
  defstruct [
    :command,
    :kind,
    :dispatcher,
    :registered_by,
    correlation_id: nil,
    causation_id: nil,
    actor: nil,
    assigns: %{},
    private: %{},
    response: nil
  ]

  @type kind :: :command | :query

  @type t :: %__MODULE__{
          command: struct(),
          kind: kind(),
          dispatcher: module(),
          registered_by: module(),
          correlation_id: term() | nil,
          causation_id: term() | nil,
          actor: term() | nil,
          assigns: map(),
          private: map(),
          response: response() | nil
        }

  @type response :: :ok | {:ok, struct()} | {:error, term()}

  @doc """
  Builds a context from a command and caller options.

  Dispatchers build the struct inline at compile time; this is the runtime equivalent, used by test helpers and by
  anything that needs a context without going through a dispatcher.

  `overrides` accepts `:kind`, `:dispatcher` and `:registered_by`.
  """
  @spec new(struct(), DispatchOptions.t(), keyword()) :: t()
  def new(command, %DispatchOptions{} = options \\ %DispatchOptions{}, overrides \\ [])
      when is_struct(command) do
    dispatcher = Keyword.get(overrides, :dispatcher)

    %__MODULE__{
      command: command,
      kind: Keyword.get(overrides, :kind, :command),
      dispatcher: dispatcher,
      registered_by: Keyword.get(overrides, :registered_by, dispatcher),
      correlation_id: options.correlation_id,
      causation_id: options.causation_id,
      actor: options.actor,
      assigns: options.assigns,
      private: Keyword.get(overrides, :private, %{})
    }
  end

  @doc """
  Assigns a value into host-app space.
  """
  @spec assign(t(), atom(), term()) :: t()
  def assign(%__MODULE__{} = context, key, value) when is_atom(key) do
    %{context | assigns: Map.put(context.assigns, key, value)}
  end

  @doc """
  Puts a value into middleware scratch space under the owning module's key.
  """
  @spec put_private(t(), module(), term()) :: t()
  def put_private(%__MODULE__{} = context, owner, value) when is_atom(owner) do
    %{context | private: Map.put(context.private, owner, value)}
  end

  @doc """
  Puts the response the pipeline carries back out.

  A middleware that calls `next` receives a context that already carries a response. One that halts sets its own.

  ## Example

      def call(context, next, _options) do
        if allowed?(context) do
          next.(context)
        else
          Context.put_response(context, {:error, :unauthorized})
        end
      end
  """
  @spec put_response(t(), response()) :: t()
  def put_response(%__MODULE__{} = context, response) do
    %{context | response: response}
  end

  @doc """
  Reads a value out of middleware scratch space.
  """
  @spec get_private(t(), module(), term()) :: term()
  def get_private(%__MODULE__{} = context, owner, default \\ nil) when is_atom(owner) do
    Map.get(context.private, owner, default)
  end
end

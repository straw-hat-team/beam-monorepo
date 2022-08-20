defmodule OnePiece.Commanded.Helpers do
  @moduledoc """
  A Swiss Army Knife Helper Module.
  """

  @type error_context :: Commanded.Event.FailureContext.t() | map()

  @type commanded_dispatch_response ::
          :ok
          | {:ok, aggregate_state :: struct()}
          | {:ok, aggregate_version :: non_neg_integer()}
          | {:ok, execution_result :: Commanded.Commands.ExecutionResult.t()}
          | {:error, :unregistered_command}
          | {:error, :consistency_timeout}
          | {:error, reason :: term()}

  @doc """
  Deprecated, it has the same behavior as `OnePiece.Commanded.Id.new/0`.
  """
  @spec generate_uuid :: String.t()
  @deprecated "Use `OnePiece.Commanded.Id.new/0` instead."
  defdelegate generate_uuid, to: OnePiece.Commanded.Id, as: :new

  @doc """
  Transforms the given `source` map or struct into the `target` struct.
  """
  @spec struct_from(source :: struct(), target :: struct()) :: struct()
  def struct_from(%_{} = source, target) do
    struct(target, Map.from_struct(source))
  end

  @spec struct_from(attrs :: map(), target :: module()) :: struct()
  def struct_from(attrs, target) do
    struct(target, attrs)
  end

  @doc false
  @spec defines_struct?(mod :: module()) :: boolean()
  def defines_struct?(mod) do
    :functions
    |> mod.__info__()
    |> Keyword.get(:__struct__)
    |> Kernel.!=(nil)
  end

  @doc """
  Copy the information from the `source` map into the given `target` map.

      iex> OnePiece.Commanded.Helpers.cast_to(%{}, %{name: "ubi-wan", last_name: "kenobi"}, [:last_name])
      %{last_name: "kenobi"}
  """
  @spec cast_to(target :: map, source :: map, keys :: [Map.key()]) :: map
  def cast_to(target, source, keys) do
    Map.merge(target, Map.take(source, keys))
  end

  @doc """
  Returns a keyword list containing the "correlation id" and "causation id" tracing.

      iex> OnePiece.Commanded.Helpers.tracing_from_metadata(%{
      ...>   event_id: "26eb06fe-9ba6-4f58-a2dd-2bdba73de4f2",
      ...>   correlation_id: "f634ba94-145c-4fa7-bf7f-0d73dd83b446"
      ...> })
      ...>
      [causation_id: "26eb06fe-9ba6-4f58-a2dd-2bdba73de4f2", correlation_id: "f634ba94-145c-4fa7-bf7f-0d73dd83b446"]

  Useful when dispatching commands to copy-forward `t:Commanded.Event.Handler.metadata/0` tracing information.

      defmodule MyProcessor do
          application: MyApp,
        use Commanded.Event.Handler,
          name: "my_processor"

        alias OnePiece.Commanded.Helpers

        def handle(%MyEvent{} = event, metadata) do
          MyApp.dispatch(
            %MyCommand{},
            # copy-forward the information
            Helpers.tracing_from_metadata(metadata)
          )
        end
      end
  """
  @spec tracing_from_metadata(metadata :: Commanded.Event.Handler.metadata()) :: [
          causation_id: String.t(),
          correlation_id: String.t()
        ]
  def tracing_from_metadata(metadata) do
    [causation_id: metadata.event_id, correlation_id: metadata.correlation_id]
  end

  @doc """
  Adds the "correlation id" and "causation id" tracing to an existing keyword list configuration option.

      iex> OnePiece.Commanded.Helpers.tracing_from_metadata([timeout: 30_000], %{
      ...>   event_id: "26eb06fe-9ba6-4f58-a2dd-2bdba73de4f2",
      ...>   correlation_id: "f634ba94-145c-4fa7-bf7f-0d73dd83b446"
      ...> })
      ...>
      [timeout: 30_000, causation_id: "26eb06fe-9ba6-4f58-a2dd-2bdba73de4f2", correlation_id: "f634ba94-145c-4fa7-bf7f-0d73dd83b446"]

  Useful when dispatching commands to copy-forward the `t:Commanded.Event.Handler.metadata/0` tracing information and
  wants to also add other keyword list options.

      defmodule MyProcessor do
        use Commanded.Event.Handler,
          application: MyApp,
          name: "my_processor"

        alias OnePiece.Commanded.Helpers

        def handle(%MyEvent{} = event, metadata) do
          MyApp.dispatch(
            %MyCommand{},
            # copy-forward the information
            Helpers.tracing_from_metadata([timeout: 30_000], metadata)
          )
        end
      end
  """
  @spec tracing_from_metadata(opts :: keyword, metadata :: Commanded.Event.Handler.metadata()) :: [
          causation_id: String.t(),
          correlation_id: String.t()
        ]
  def tracing_from_metadata(opts, metadata) do
    Keyword.merge(opts, tracing_from_metadata(metadata))
  end

  @doc """
  Returns `skip` or a `retry` response.

  When the `c:Commanded.Application.dispatch/1` or `c:Commanded.Application.dispatch/2` returns an `:skip` otherwise,
  returns a `:retry` response. Useful when you are doing error handling in your `c:Commanded.Event.Handler.error/3`.

      iex> success_dispatch = fn _ -> :ok end
      ...> OnePiece.Commanded.Helpers.skip_or_retry(success_dispatch.(%{}), %{})
      :skip

      iex> success_dispatch = fn _ -> {:ok, %{}} end
      ...> OnePiece.Commanded.Helpers.skip_or_retry(success_dispatch.(%{}), %{})
      :skip

      iex> failure_dispatch = fn _ -> {:error, :ooops} end
      ...> OnePiece.Commanded.Helpers.skip_or_retry(failure_dispatch.(%{}), %{failures: 1})
      {:retry, %{failures: 1}}
  """
  @spec skip_or_retry(tuple_response :: commanded_dispatch_response, context :: error_context) ::
          :skip | {:retry, error_context}
  def skip_or_retry(:ok, _context), do: :skip
  def skip_or_retry({:ok, _}, _context), do: :skip
  def skip_or_retry(_, context), do: {:retry, context}

  @doc """
  Returns `skip` or a `retry` response with a given delay.

  When the `c:Commanded.Application.dispatch/1` or `c:Commanded.Application.dispatch/2` returns an `:skip` otherwise,
  returns a `:retry` response. Useful when you are doing error handling in your `c:Commanded.Event.Handler.error/3`.

      iex> success_dispatch = fn _ -> :ok end
      ...> OnePiece.Commanded.Helpers.skip_or_retry(success_dispatch.(%{}), 5_000, %{})
      :skip

      iex> success_dispatch = fn _ -> {:ok, %{}} end
      ...> OnePiece.Commanded.Helpers.skip_or_retry(success_dispatch.(%{}), 5_000, %{})
      :skip

      iex> failure_dispatch = fn _ -> {:error, :ooops} end
      ...> OnePiece.Commanded.Helpers.skip_or_retry(failure_dispatch.(%{}), 5_000, %{failures: 1})
      {:retry, 5_000, %{failures: 1}}
  """
  @spec skip_or_retry(
          tuple_response :: commanded_dispatch_response,
          delay :: non_neg_integer(),
          context :: error_context
        ) ::
          :skip | {:retry, non_neg_integer(), error_context}
  def skip_or_retry(:ok, _delay, _context), do: :skip
  def skip_or_retry({:ok, _}, _delay, _context), do: :skip
  def skip_or_retry(_, delay, context), do: {:retry, delay, context}
end

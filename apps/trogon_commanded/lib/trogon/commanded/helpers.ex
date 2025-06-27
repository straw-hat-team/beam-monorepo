defmodule Trogon.Commanded.Helpers do
  @moduledoc """
  A Swiss Army Knife Helper Module.
  """

  alias Commanded.Event.FailureContext

  @type error_context :: FailureContext.t() | map()

  @type commanded_dispatch_response ::
          :ok
          | {:ok, aggregate_state :: struct()}
          | {:ok, aggregate_version :: non_neg_integer()}
          | {:ok, execution_result :: Commanded.Commands.ExecutionResult.t()}
          | {:error, :unregistered_command}
          | {:error, :consistency_timeout}
          | {:error, reason :: term()}

  @doc """
  Deprecated, it has the same behavior as `Trogon.Commanded.Id.new/0`.
  """
  @spec generate_uuid :: String.t()
  @deprecated "Use `Trogon.Commanded.Id.new/0` instead."
  defdelegate generate_uuid, to: Trogon.Commanded.Id, as: :new

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

      iex> Trogon.Commanded.Helpers.cast_to(%{}, %{name: "ubi-wan", last_name: "kenobi"}, [:last_name])
      %{last_name: "kenobi"}
  """
  @spec cast_to(target :: map, source :: map, keys :: [Map.key()]) :: map
  def cast_to(target, source, keys) do
    Map.merge(target, Map.take(source, keys))
  end

  @doc """
  Returns a keyword list containing the "correlation id" and "causation id" tracing.

      iex> Trogon.Commanded.Helpers.tracing_from_metadata(%{
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

        alias Trogon.Commanded.Helpers

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

      iex> Trogon.Commanded.Helpers.tracing_from_metadata([timeout: 30_000], %{
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

        alias Trogon.Commanded.Helpers

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
      ...> Trogon.Commanded.Helpers.skip_or_retry(success_dispatch.(%{}), %{})
      :skip

      iex> success_dispatch = fn _ -> {:ok, %{}} end
      ...> Trogon.Commanded.Helpers.skip_or_retry(success_dispatch.(%{}), %{})
      :skip

      iex> failure_dispatch = fn _ -> {:error, :ooops} end
      ...> Trogon.Commanded.Helpers.skip_or_retry(failure_dispatch.(%{}), %{failures: 1})
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
      ...> Trogon.Commanded.Helpers.skip_or_retry(success_dispatch.(%{}), 5_000, %{})
      :skip

      iex> success_dispatch = fn _ -> {:ok, %{}} end
      ...> Trogon.Commanded.Helpers.skip_or_retry(success_dispatch.(%{}), 5_000, %{})
      :skip

      iex> failure_dispatch = fn _ -> {:error, :ooops} end
      ...> Trogon.Commanded.Helpers.skip_or_retry(failure_dispatch.(%{}), 5_000, %{failures: 1})
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

  @doc """
  Increase the failure counter from `t:Commanded.Event.FailureContext.t/0` context by one.

        iex> Trogon.Commanded.Helpers.increase_failure_counter(%Commanded.Event.FailureContext{context: %{failures_count: 1}})
        %{failures_count: 2}
  """
  @spec increase_failure_counter(failure_context :: FailureContext.t()) :: map()
  def increase_failure_counter(%FailureContext{} = failure_context) do
    Map.update(failure_context.context, :failures_count, 1, &(&1 + 1))
  end

  @doc """
  Ignores a specific error from a command dispatch result.

  This function takes a dispatch result and an error term. If the result represents an error that matches the provided
  error term, the function returns `:ok`. Otherwise, it returns the original result.

  This is useful when an error condition should be treated as a successful operation under specific circumstances.

  ## Examples

      iex> Trogon.Commanded.Helpers.ignore_error({:error, :idempotency_failure}, :idempotency_failure)
      :ok

      iex> Trogon.Commanded.Helpers.ignore_error({:error, :something_went_wrong}, :idempotency_failure)
      {:error, :something_went_wrong}

      iex> Trogon.Commanded.Helpers.ignore_error(:ok, :idempotency_failure)
      :ok

      iex> Trogon.Commanded.Helpers.ignore_error({:ok, %{name: "Billy"}}, :idempotency_failure)
      {:ok, %{name: "Billy"}}
  """
  @spec ignore_error(result :: commanded_dispatch_response, error: any) :: commanded_dispatch_response
  def ignore_error({:error, expected_error}, expected_error), do: :ok
  def ignore_error(result, _expected_error), do: result

  @doc false
  def get_primary_key({identifier, identifier_type}) do
    {identifier, identifier_type}
  end

  def get_primary_key(identifier) when is_atom(identifier) do
    {identifier, :string}
  end
end

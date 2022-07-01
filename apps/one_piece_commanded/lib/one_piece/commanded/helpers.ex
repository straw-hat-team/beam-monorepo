defmodule OnePiece.Commanded.Helpers do
  @moduledoc """
  A Swiss Army Knife Helper Module.
  """

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
          application: Hmbradley,
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
          application: Hmbradley,
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
end

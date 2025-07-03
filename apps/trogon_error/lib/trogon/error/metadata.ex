defmodule Trogon.Error.Metadata do
  @moduledoc """
  A structured container for error metadata with support for visibility controls.

  This module provides a wrapper around metadata entries, where each entry
  is a `MetadataValue` struct containing both the value and its visibility level.

  Implements the `Access` behavior for convenient map-like access to metadata entries.

  ## Examples

      iex> metadata = Trogon.Error.Metadata.new(%{"user_id" => "123", "action" => "login"})
      iex> metadata["user_id"].value
      "123"
      iex> metadata["user_id"].visibility
      :INTERNAL

  """

  alias Trogon.Error.MetadataValue

  @enforce_keys [:entries]
  defstruct [:entries]

  @type t :: %__MODULE__{entries: %{String.t() => MetadataValue.t()}}

  @doc """
  Guard that checks if metadata is empty (has no entries).

  ## Examples

      iex> import Trogon.Error.Metadata, only: [is_empty_metadata: 1]
      iex> empty = Trogon.Error.Metadata.new()
      iex> is_empty_metadata(empty)
      true

      iex> import Trogon.Error.Metadata, only: [is_empty_metadata: 1]
      iex> with_data = Trogon.Error.Metadata.new(%{"key" => "value"})
      iex> is_empty_metadata(with_data)
      false

  """
  defguard is_empty_metadata(metadata) when is_struct(metadata, __MODULE__) and map_size(metadata.entries) == 0

  @behaviour Access

  @doc """
  Fetches a metadata value by key.

  ## Examples

      iex> metadata = Trogon.Error.Metadata.new(%{"user_id" => "123"})
      iex> Trogon.Error.Metadata.fetch(metadata, "user_id")
      {:ok, %Trogon.Error.MetadataValue{value: "123", visibility: :internal}}

      iex> metadata = Trogon.Error.Metadata.new(%{})
      iex> Trogon.Error.Metadata.fetch(metadata, "missing")
      :error

  """
  @impl Access
  def fetch(%__MODULE__{entries: entries}, key) do
    Map.fetch(entries, key)
  end

  @doc """
  Gets and updates a metadata entry.

  ## Examples

      iex> metadata = Trogon.Error.Metadata.new(%{"count" => "1"})
      iex> {old_value, new_metadata} = Trogon.Error.Metadata.get_and_update(metadata, "count", fn old ->
      ...>   new_value = %Trogon.Error.MetadataValue{value: "2", visibility: :internal}
      ...>   {old, new_value}
      ...> end)
      iex> old_value.value
      "1"
      iex> new_metadata["count"].value
      "2"

  """
  @impl Access
  def get_and_update(%__MODULE__{entries: entries} = metadata, key, fun) do
    {value, new_entries} = Map.get_and_update(entries, key, fun)
    {value, %{metadata | entries: new_entries}}
  end

  @doc """
  Pops a metadata entry by key.

  ## Examples

      iex> metadata = Trogon.Error.Metadata.new(%{"user_id" => "123", "action" => "login"})
      iex> {value, new_metadata} = Trogon.Error.Metadata.pop(metadata, "user_id")
      iex> value.value
      "123"
      iex> map_size(new_metadata.entries)
      1

  """
  @impl Access
  def pop(%__MODULE__{entries: entries} = metadata, key) do
    {value, new_entries} = Map.pop(entries, key)
    {value, %{metadata | entries: new_entries}}
  end

  @doc """
  Creates a new empty Metadata struct.

  ## Examples

      iex> Trogon.Error.Metadata.new()
      %Trogon.Error.Metadata{entries: %{}}

  """
  @spec new() :: t()
  def new do
    %__MODULE__{entries: %{}}
  end

  @doc """
  Creates a new Metadata struct from a map of entries.

  Accepts various formats for metadata values:
  - Simple values (converted to MetadataValue with :internal visibility)
  - Tuples with explicit visibility: `{value, visibility}`
  - Pre-existing MetadataValue structs

  ## Examples

      iex> metadata = Trogon.Error.Metadata.new(%{"user_id" => "123", "secret" => {"api-key", :PRIVATE}})
      iex> metadata["user_id"].visibility
      :INTERNAL
      iex> metadata["secret"].visibility
      :PRIVATE

  """
  @spec new(%{term() => MetadataValue.t() | {term(), MetadataValue.visibility()} | term()}) :: t()
  def new(entries) do
    %__MODULE__{entries: Map.new(entries, &to_entry/1)}
  end

  @doc """
  Merges two Metadata structs, with the second taking precedence for duplicate keys.

  ## Examples

      iex> metadata1 = Trogon.Error.Metadata.new(%{"user_id" => "123", "action" => "login"})
      iex> metadata2 = Trogon.Error.Metadata.new(%{"user_id" => "456", "session" => "abc"})
      iex> merged = Trogon.Error.Metadata.merge(metadata1, metadata2)
      iex> merged["user_id"].value
      "456"
      iex> map_size(merged.entries)
      3

  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{entries: entries1}, %__MODULE__{entries: entries2}) do
    %__MODULE__{entries: Map.merge(entries1, entries2)}
  end

  defp to_entry({key, %MetadataValue{} = value}) do
    {entry_key(key), value}
  end

  defp to_entry({key, {value, visibility}}) do
    {entry_key(key), MetadataValue.new(value, visibility)}
  end

  defp to_entry({key, value}) do
    {entry_key(key), MetadataValue.new(value)}
  end

  defp entry_key(key) when is_binary(key), do: key
  defp entry_key(key), do: to_string(key)
end

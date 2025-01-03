defmodule ElixirStdlib.ExtendedMap do
  @moduledoc """
  Extended Map module
  """

  @doc """
  Convert all keys in a map to the specified type.

  - `:strings` - Convert all keys to binary strings.
  - `:atoms` - Convert all keys to atoms using `String.to_atom/1`.
  - `:atoms!` - Convert all keys to atoms using `String.to_existing_atom/1`.

  ## Options

  - `:recursive` - Convert keys in nested maps and lists.

  ## Examples

  Convert all keys to binary strings.

      iex> ElixirStdlib.ExtendedMap.to_keys(%{a: 1, b: 2}, :strings)
      %{"a" => 1, "b" => 2}

      iex> ElixirStdlib.ExtendedMap.to_keys(%{a: %{b: 2}}, :strings)
      %{"a" => %{b: 2}}

      iex> ElixirStdlib.ExtendedMap.to_keys(%{a: [b: 2]}, :strings)
      %{"a" => [b: 2]}

      iex> ElixirStdlib.ExtendedMap.to_keys(%{a: [%{b: 2}, %{c: 3}]}, :strings, recursive: true)
      %{"a" => [%{"b" => 2}, %{"c" => 3}]}

  Convert all keys to atoms.

      iex> ElixirStdlib.ExtendedMap.to_keys(%{"a" => 1, "b" => 2}, :atoms)
      %{a: 1, b: 2}

      iex> ElixirStdlib.ExtendedMap.to_keys(%{"a" => %{"b" => 2}}, :atoms)
      %{a: %{"b" => 2}}

      iex> ElixirStdlib.ExtendedMap.to_keys(%{"a" => [b: 2]}, :atoms)
      %{a: [b: 2]}

      iex> ElixirStdlib.ExtendedMap.to_keys(%{"a" => %{"b" => 2}, "c" => 3}, :atoms, recursive: true)
      %{a: %{b: 2}, c: 3}

  Convert all keys to existing atoms.

      iex> ElixirStdlib.ExtendedMap.to_keys(%{"a" => 1, "b" => 2}, :atoms!)
      %{a: 1, b: 2}

      iex> ElixirStdlib.ExtendedMap.to_keys(%{"a" => %{b: 2}}, :atoms!)
      %{a: %{b: 2}}

      iex> ElixirStdlib.ExtendedMap.to_keys(%{"a" => [b: 2]}, :atoms!)
      %{a: [b: 2]}
  """
  @spec to_keys(map(), :strings | :atoms | :atoms!) :: map()
  def to_keys(map, key_type, opts \\ []) when is_map(map) do
    do_keys_as(map, key_type, opts)
  end

  defp do_keys_as({k, v}, :atoms, opts) when is_binary(k) do
    value = if opts[:recursive], do: do_keys_as(v, :atoms, opts), else: v
    {String.to_atom(k), value}
  end

  defp do_keys_as({k, v}, :atoms!, opts) when is_binary(k) do
    value = if opts[:recursive], do: do_keys_as(v, :atoms!, opts), else: v
    {String.to_existing_atom(k), value}
  end

  defp do_keys_as({k, v}, :strings, opts) when is_atom(k) do
    value = if opts[:recursive], do: do_keys_as(v, :strings, opts), else: v
    {Atom.to_string(k), value}
  end

  defp do_keys_as(map, key_type, opts) when is_map(map) do
    Map.new(map, &do_keys_as(&1, key_type, opts))
  end

  defp do_keys_as(value, key_type, opts) when is_list(value) do
    Enum.map(value, &do_keys_as(&1, key_type, opts))
  end

  defp do_keys_as(value, _key_type, _opts) do
    value
  end
end

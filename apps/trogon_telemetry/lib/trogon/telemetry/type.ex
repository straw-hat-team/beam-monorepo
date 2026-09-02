defmodule Trogon.Telemetry.Type do
  @moduledoc """
  The type of a declared field.

  A type is either one of the built-in shorthands or a module implementing this behaviour. Modules are
  how value objects keep their identity all the way to the handler: a `project_id` attribute stays a
  `MyApp.ProjectId` struct instead of collapsing into a string at the call site.

  Nothing is flattened while the event travels. `dump/2` exists for the exporters that eventually need a
  scalar, such as a metric tag or a tracing attribute.
  """

  @typedoc """
  Built-in shorthands, or a module implementing `Trogon.Telemetry.Type`.
  """
  @type t ::
          :atom
          | :boolean
          | :float
          | :integer
          | :number
          | :reference
          | :string
          | :term
          | {:enum, [atom(), ...]}
          | {:array, t()}
          | module()

  @doc """
  Converts a value into a scalar an exporter can carry.
  """
  @callback dump(value :: term()) :: term()

  @builtin [:atom, :boolean, :float, :integer, :number, :reference, :string, :term]

  @doc """
  Whether a type is one this package understands.

  Modules are accepted without being loaded, since a value object may still be compiling when the event
  declaring it is compiled.
  """
  @spec valid?(term()) :: boolean()
  def valid?(type) when type in @builtin, do: true
  def valid?({:enum, values}) when is_list(values) and values != [], do: Enum.all?(values, &is_atom/1)
  def valid?({:array, inner}), do: valid?(inner)
  def valid?(module) when is_atom(module), do: match?("Elixir." <> _, Atom.to_string(module))
  def valid?(_type), do: false

  @doc """
  Whether a type only ever holds numbers, which is what `:telemetry` measurements require.
  """
  @spec numeric?(t()) :: boolean()
  def numeric?(type) when type in [:float, :integer, :number], do: true
  def numeric?(_type), do: false

  @doc """
  Flattens a value into a scalar, for exporters that cannot carry rich types.
  """
  @spec dump(t(), term()) :: term()
  def dump(_type, nil), do: nil
  def dump(type, value) when type in @builtin, do: value
  def dump({:enum, _values}, value), do: value
  def dump({:array, inner}, values) when is_list(values), do: Enum.map(values, &dump(inner, &1))
  def dump(module, value) when is_atom(module), do: module.dump(value)

  @doc """
  A human readable name for a type, used by the generated documentation.
  """
  @spec to_string(t()) :: String.t()
  def to_string(type) when type in @builtin, do: Atom.to_string(type)
  def to_string({:enum, values}), do: Enum.map_join(values, " \\| ", &"`#{inspect(&1)}`")
  def to_string({:array, inner}), do: "list of #{__MODULE__.to_string(inner)}"
  def to_string(module) when is_atom(module), do: "`#{inspect(module)}`"
end

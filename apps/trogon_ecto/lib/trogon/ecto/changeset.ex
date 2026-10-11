defmodule Trogon.Ecto.Changeset do
  @moduledoc """
  Extends `Ecto.Changeset` with validations for conventions shared across
  changesets, and turns a failed changeset into data an API layer can report.

      import Trogon.Ecto.Changeset

      def changeset(job, attrs) do
        job
        |> cast(attrs, [:name, :completed_at])
        |> validate_unset(:completed_at, message: "cannot be set on creation")
      end
  """

  alias Ecto.Changeset
  alias Trogon.Ecto.ErrorMessage
  alias Trogon.Ecto.FieldViolation

  @derived_metadata_keys [:validation, :constraint, :kind, :code, :type]

  @doc """
  Validates that a field is unset, the exact opposite of `Ecto.Changeset.validate_required/3`.

  Use it for a field the caller is not allowed to supply, where silently dropping
  the value would be worse than telling them, such as a server-assigned field
  arriving from an untrusted payload.

  A field counts as set unless `Ecto.Changeset.field_missing?/2` says it is missing,
  so `nil` and anything in the changeset's `:empty_values` (`""` by default) pass, as
  does a whitespace-only string, which `Ecto.Changeset.cast/4` trims down to one.
  That makes it exactly the negation of `validate_required/3`: no value can fail both.

  ## Options

  - `:message` - the message on failure, defaults to "must be blank".

  ## Examples

      iex> types = %{completed_at: :string}
      iex> changeset = Ecto.Changeset.cast({%{completed_at: nil}, types}, %{}, Map.keys(types))
      iex> Trogon.Ecto.Changeset.validate_unset(changeset, :completed_at).valid?
      true

      iex> types = %{completed_at: :string}
      iex> changeset = Ecto.Changeset.cast({%{completed_at: nil}, types}, %{completed_at: "now"}, Map.keys(types))
      iex> changeset = Trogon.Ecto.Changeset.validate_unset(changeset, :completed_at)
      iex> changeset.errors
      [completed_at: {"must be blank", [validation: :unset]}]
  """
  @spec validate_unset(Changeset.t(), atom() | [atom()], Keyword.t()) :: Changeset.t()
  def validate_unset(changeset, fields, opts \\ [])

  def validate_unset(%Changeset{} = changeset, fields, opts) when is_list(fields) do
    Enum.reduce(fields, changeset, &validate_unset(&2, &1, opts))
  end

  def validate_unset(%Changeset{} = changeset, field, opts) when is_atom(field) do
    if Changeset.field_missing?(changeset, field) do
      changeset
    else
      Changeset.add_error(changeset, field, message(opts), validation: :unset)
    end
  end

  defp message(opts), do: Keyword.get(opts, :message, "must be blank")

  @doc """
  Flattens every error in a changeset, however deeply nested, into a list of
  `Trogon.Ecto.FieldViolation`.

  This is the shape an API layer needs and a changeset will not give you: one
  entry per error, each naming the field it is about with a path a caller can
  follow, a machine readable reason to branch on, a message already interpolated
  so nothing downstream has to know about `%{count}`, and that same message
  before interpolation together with its bindings, for a caller that would rather
  render it itself.

  Embeds, associations, and `PolymorphicEmbed` fields are all traversed. Members
  of a collection are indexed, so a failure two levels down reads `"items[0].sku"`.

  A member being replaced is dropped before anything is indexed. Ecto keeps those
  on the front of the collection it traverses, so an index taken straight from a
  changeset counts values that are on their way out and points the caller at the
  wrong member of the list they sent.

  Violations are sorted by field path, so equivalent changesets produce byte for
  byte equivalent output. Errors on the same field keep their relative order.

  See `Trogon.Ecto.FieldViolation` for how a reason is derived.

  ## Examples

      iex> types = %{name: :string}
      iex> changeset = Ecto.Changeset.cast({%{name: nil}, types}, %{}, Map.keys(types))
      iex> changeset = Ecto.Changeset.validate_required(changeset, [:name])
      iex> Trogon.Ecto.Changeset.field_violations(changeset)
      [
        %Trogon.Ecto.FieldViolation{
          field: "name",
          reason: :required,
          message: "can't be blank",
          template: "can't be blank",
          metadata: []
        }
      ]

      iex> types = %{title: :string}
      iex> changeset = Ecto.Changeset.cast({%{title: nil}, types}, %{title: "too long"}, Map.keys(types))
      iex> changeset = Ecto.Changeset.validate_length(changeset, :title, max: 3)
      iex> Trogon.Ecto.Changeset.field_violations(changeset)
      [
        %Trogon.Ecto.FieldViolation{
          field: "title",
          reason: :max_length,
          message: "should be at most 3 character(s)",
          template: "should be at most %{count} character(s)",
          metadata: [count: 3]
        }
      ]

      iex> types = %{age: :integer}
      iex> changeset = Ecto.Changeset.cast({%{age: nil}, types}, %{age: "old"}, Map.keys(types))
      iex> [violation] = Trogon.Ecto.Changeset.field_violations(changeset)
      iex> {violation.reason, violation.template, violation.metadata}
      {:cast, "is invalid", []}
  """
  @spec field_violations(Changeset.t()) :: [FieldViolation.t()]
  def field_violations(%Changeset{} = changeset) do
    changeset
    |> reject_replaced_changes()
    |> PolymorphicEmbed.traverse_errors(&to_violation_parts/1)
    |> to_field_violations("")
    |> Enum.sort_by(& &1.field)
  end

  defp reject_replaced_changes(values) when is_list(values) do
    values
    |> Enum.map(&reject_replaced_changes/1)
    |> Enum.reject(&match?(%Changeset{action: :replace}, &1))
  end

  defp reject_replaced_changes(%Changeset{} = changeset) do
    %{changeset | changes: Map.new(changeset.changes, &reject_replaced_change/1)}
  end

  defp reject_replaced_changes(value), do: value

  defp reject_replaced_change({key, value}), do: {key, reject_replaced_changes(value)}

  defp to_violation_parts({template, opts}) do
    {ErrorMessage.interpolate({template, opts}), template, reason(Map.new(opts)), to_metadata(template, opts)}
  end

  defp to_metadata(template, opts) do
    Enum.reject(opts, fn {key, _value} ->
      key in @derived_metadata_keys and not ErrorMessage.interpolates?(template, key)
    end)
  end

  defp reason(%{code: code}) when is_atom(code), do: code
  defp reason(%{validation: :length, kind: :min}), do: :min_length
  defp reason(%{validation: :length, kind: :max}), do: :max_length
  defp reason(%{validation: :length}), do: :length
  defp reason(%{validation: :number, kind: kind}), do: kind
  defp reason(%{validation: validation}), do: validation
  defp reason(%{constraint: :unique}), do: :unique_constraint
  defp reason(%{constraint: :foreign}), do: :foreign_constraint
  defp reason(%{constraint: :assoc}), do: :assoc_constraint
  defp reason(%{constraint: :no_assoc}), do: :no_assoc_constraint
  defp reason(%{constraint: :check}), do: :check_constraint
  defp reason(%{constraint: :exclusion}), do: :exclusion_constraint
  defp reason(%{constraint: _constraint}), do: :constraint
  defp reason(_opts), do: :unknown

  defp to_field_violations(errors, path) do
    Enum.flat_map(errors, &field_to_violations(&1, path))
  end

  defp field_to_violations({field, value}, path) do
    field_path = join_field_path(path, field)

    case value do
      parts when is_list(parts) ->
        parts
        |> Enum.with_index()
        |> Enum.flat_map(&indexed_to_violations(&1, field_path))

      nested when is_map(nested) ->
        to_field_violations(nested, field_path)
    end
  end

  defp indexed_to_violations({{message, template, reason, metadata}, _index}, field_path)
       when is_binary(message) do
    [
      %FieldViolation{
        field: field_path,
        reason: reason,
        message: message,
        template: template,
        metadata: metadata
      }
    ]
  end

  defp indexed_to_violations({nested, index}, field_path) do
    to_field_violations(nested, "#{field_path}[#{index}]")
  end

  defp join_field_path("", field), do: to_string(field)
  defp join_field_path(path, field), do: "#{path}.#{field}"
end

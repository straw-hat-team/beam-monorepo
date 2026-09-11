defmodule Trogon.Ecto.Changeset do
  @moduledoc """
  Extends `Ecto.Changeset` with validations for conventions shared across changesets.

      import Trogon.Ecto.Changeset

      def changeset(job, attrs) do
        job
        |> cast(attrs, [:name, :completed_at])
        |> validate_unset(:completed_at, message: "cannot be set on creation")
      end
  """

  alias Ecto.Changeset

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
end

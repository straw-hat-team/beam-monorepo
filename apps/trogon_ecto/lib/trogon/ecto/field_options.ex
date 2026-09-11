defmodule Trogon.Ecto.FieldOptions do
  @moduledoc false

  # The options `Ecto.Schema.field/3` documents, which Ecto passes straight
  # through to `Ecto.ParameterizedType.init/1` without checking them, plus the
  # two keys it injects there itself. Kept in one place so a parameterized type
  # can reject a misspelled option of its own without rejecting these.
  #
  # Sourced from the `field/3` @doc in `Ecto.Schema`, not from its private
  # `@field_opts` attribute: that one is shared with the association macros and
  # so also lists options a field has no use for.
  @ecto_keys [
    :default,
    :source,
    :autogenerate,
    :read_after_writes,
    :virtual,
    :primary_key,
    :load_in_query,
    :redact,
    :skip_default_validation,
    :writable,
    :on_writable_violation
  ]

  @injected_keys [:field, :schema]

  @spec keys() :: [atom()]
  def keys, do: @ecto_keys ++ @injected_keys

  @spec nimble_schema() :: keyword()
  def nimble_schema, do: Enum.map(keys(), &{&1, [type: :any, doc: false]})
end

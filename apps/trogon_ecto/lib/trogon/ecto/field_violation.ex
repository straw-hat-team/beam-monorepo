defmodule Trogon.Ecto.FieldViolation do
  @moduledoc """
  A single changeset error, reduced to the field it is about, why it failed, and
  what to tell the caller, both as a message and as the template and bindings it
  was rendered from.

  Built by `Trogon.Ecto.Changeset.field_violations/1`.
  """

  @enforce_keys [:field, :reason, :message, :template, :metadata]
  defstruct [:field, :reason, :message, :template, :metadata]

  @typedoc """
  The path to the field that failed, with nested fields joined by `.` and
  collection members indexed, such as `"items[0].sku"`.
  """
  @type field :: String.t()

  @typedoc """
  Why the field failed, as a stable atom derived from the error's metadata.

  Validations report the `:validation` that failed, narrowed by its `:kind` where
  Ecto provides one, so `validate_length/3` reports `:min_length` or `:max_length`
  rather than `:length`. Constraints report a `_constraint` suffixed atom, keeping
  `validate_exclusion/4` (`:exclusion`) distinct from `exclusion_constraint/3`
  (`:exclusion_constraint`).

  An error added with an atom `:code` in its metadata reports that instead, which
  is the escape hatch for a reason that cannot be inferred. Anything left over is
  `:unknown`.
  """
  @type reason :: atom()

  @typedoc """
  The message before interpolation, exactly as Ecto or a validation wrote it, with
  its `%{...}` placeholders intact.

  Together with `t:metadata/0` this is what a caller needs to render the message
  itself, in its own language or its own wording, instead of taking ours:

      Gettext.dgettext(MyApp.Gettext, "errors", violation.template, violation.metadata)

  Interpolating the template with the metadata always reproduces `:message`.
  """
  @type template :: String.t()

  @typedoc """
  The bindings the template was rendered with, in the order Ecto put them there.

  This is the bound a caller needs to render its own message, so a `:max_length`
  violation carries `[count: 5]`, an `:inclusion` violation carries the `:enum` it
  was checked against, and a `:greater_than` violation carries the `:number`.

  A key that only repeats what `t:reason/0` already says is left out, namely
  `:validation`, `:constraint`, `:kind`, and `:code`, as is Ecto's `:type`, which
  it injects into every cast error and which describes the field rather than the
  failure. A key is kept regardless if the template interpolates it, so the
  template and the metadata are never out of step.

  Everything else survives, including `:constraint_name`, which names a database
  index. Decide whether that should reach the caller before passing this through.
  """
  @type metadata :: keyword()

  @type t :: %__MODULE__{
          field: field(),
          reason: reason(),
          message: String.t(),
          template: template(),
          metadata: metadata()
        }
end

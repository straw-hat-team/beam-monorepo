defmodule Trogon.Ecto.AnnotationMap do
  alias Trogon.Ecto.FieldOptions
  alias Trogon.Ecto.StringMap

  @forced [key_format: :qualified_name_ignoring_case, value_format: :any]

  @opts_schema NimbleOptions.new!(
                 [
                   max_key_length: [
                     type: {:or, [:pos_integer, {:in, [:infinity]}]},
                     default: :infinity,
                     doc: "Maximum key length in bytes, whole key included."
                   ],
                   max_value_length: [
                     type: {:or, [:pos_integer, {:in, [:infinity]}]},
                     default: :infinity,
                     doc: "Maximum value length in bytes."
                   ]
                 ] ++ FieldOptions.nimble_schema()
               )

  @moduledoc """
  Non-identifying metadata, the Kubernetes `metadata.annotations` rules under a name.

      defmodule Deployment do
        use Ecto.Schema

        schema "deployments" do
          field :annotations, Trogon.Ecto.AnnotationMap, max_value_length: 4_096
        end
      end

  Nothing selects on an annotation, so only the key is constrained:

  - a key is a qualified name, `name` or `prefix/name`, matched against its
    lowercased form, which is what `ValidateAnnotations` does. `Example.com/tier`
    is a valid annotation key and an invalid label key.
  - a value is any string, a sentence or a JSON document alike

  See `Trogon.Ecto.StringMap` for the key rule and for the shape every entry shares
  with a label.

  Kubernetes also caps a whole annotations map at 256 KiB, which is a limit on what
  its own storage will take rather than a property of the shape, so it is left to
  you. `max_value_length` is the bound to reach for, since an unconstrained value
  is otherwise as large as the column will hold.

  The rules are the type, so `key_format` and `value_format` cannot be passed here.
  Use `Trogon.Ecto.StringMap` for a map whose rules you choose.

  ## Options

  #{NimbleOptions.docs(@opts_schema)}

  A rejected value fails the changeset with `validation: :annotation_map`, and
  otherwise reports exactly as `Trogon.Ecto.StringMap` does.
  """

  use Ecto.ParameterizedType

  @typedoc "A map of strings to strings."
  @type t :: StringMap.t()

  @typedoc "An annotation map's rules, built by Ecto from `field/3`."
  @type params :: StringMap.params()

  @impl Ecto.ParameterizedType
  @spec init(keyword()) :: params()
  def init(opts), do: StringMap.init_preset(opts, @forced, :annotation_map)

  @impl Ecto.ParameterizedType
  @spec type(params()) :: :map
  def type(params), do: StringMap.type(params)

  @impl Ecto.ParameterizedType
  @spec cast(term(), params()) :: {:ok, t() | nil} | {:error, keyword()} | :error
  def cast(value, params), do: StringMap.cast(value, params)

  @impl Ecto.ParameterizedType
  @spec load(term(), (Ecto.Type.t(), term() -> {:ok, term()} | :error), params()) ::
          {:ok, map() | nil} | :error
  def load(value, loader, params), do: StringMap.load(value, loader, params)

  @impl Ecto.ParameterizedType
  @spec dump(term(), (Ecto.Type.t(), term() -> {:ok, term()} | :error), params()) ::
          {:ok, t() | nil} | :error
  def dump(value, dumper, params), do: StringMap.dump(value, dumper, params)

  @impl Ecto.ParameterizedType
  @spec embed_as(atom(), params()) :: :dump
  def embed_as(format, params), do: StringMap.embed_as(format, params)
end

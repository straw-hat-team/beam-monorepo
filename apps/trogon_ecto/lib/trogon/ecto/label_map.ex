defmodule Trogon.Ecto.LabelMap do
  alias Trogon.Ecto.FieldOptions
  alias Trogon.Ecto.StringMap

  @forced [key_format: :qualified_name, value_format: :label_value]

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
  Identifying metadata, the Kubernetes `metadata.labels` rules under a name.

      defmodule Deployment do
        use Ecto.Schema

        schema "deployments" do
          field :labels, Trogon.Ecto.LabelMap
        end
      end

  A label is meant to be selected on, so both halves of an entry are constrained:

  - a key is a qualified name, `name` or `prefix/name`
  - a value is an empty string, or a name

  See `Trogon.Ecto.StringMap` for what those two rules are, and for the shape every
  entry shares with an annotation. Unlike an annotation key, a label key is
  case sensitive, matching `ValidateLabels` rather than `ValidateAnnotations`.

  The rules are the type, so `key_format` and `value_format` cannot be passed here.
  Use `Trogon.Ecto.StringMap` for a map whose rules you choose.

  ## Options

  #{NimbleOptions.docs(@opts_schema)}

  A rejected value fails the changeset with `validation: :label_map`, and otherwise
  reports exactly as `Trogon.Ecto.StringMap` does.
  """

  use Ecto.ParameterizedType

  @typedoc "A map of strings to strings."
  @type t :: StringMap.t()

  @typedoc "A label map's rules, built by Ecto from `field/3`."
  @type params :: StringMap.params()

  @impl Ecto.ParameterizedType
  @spec init(keyword()) :: params()
  def init(opts), do: StringMap.init_preset(opts, @forced, :label_map)

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

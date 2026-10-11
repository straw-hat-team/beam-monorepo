defmodule Trogon.Ecto.StringMap do
  alias Trogon.Ecto.FieldOptions

  @own_keys [:key_format, :value_format, :max_key_length, :max_value_length]

  @name_max_length 63
  @prefix_max_length 253
  @value_max_length 63

  @name_regex ~r/\A[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?\z/
  @prefix_regex ~r/\A[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*\z/

  @opts_schema NimbleOptions.new!(
                 [
                   key_format: [
                     type: {:in, [:any, :qualified_name, :qualified_name_ignoring_case]},
                     default: :any,
                     doc: """
                     Syntax every key must follow. `:any` accepts any string.
                     `:qualified_name` is `name` or `prefix/name`.
                     `:qualified_name_ignoring_case` is the same rule applied to
                     the lowercased key.
                     """
                   ],
                   value_format: [
                     type: {:in, [:any, :label_value]},
                     default: :any,
                     doc: """
                     Syntax every value must follow. `:any` accepts any string.
                     `:label_value` is empty, or a name.
                     """
                   ],
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
  A map of strings to strings, with the rules a key and a value must follow left
  to the field.

  It is modelled on Kubernetes, which holds `metadata.labels` and
  `metadata.annotations` as `map[string]string` and validates each of them
  differently. `Trogon.Ecto.LabelMap` and `Trogon.Ecto.AnnotationMap` are those
  two rule sets under their own names; reach for this type when neither fits.

      defmodule Deployment do
        use Ecto.Schema

        schema "deployments" do
          field :tags, Trogon.Ecto.StringMap

          field :selector, Trogon.Ecto.StringMap,
            key_format: :qualified_name,
            value_format: :label_value,
            max_value_length: 32
        end
      end

  ## Options

  #{NimbleOptions.docs(@opts_schema)}

  Every option is unset by default, so a bare `field :tags, Trogon.Ecto.StringMap`
  constrains the shape and nothing else.

  ## What a field accepts

  Every key and every value must already be a string. Nothing is converted, for the
  same reason Kubernetes rejects `replicas: 3` in a labels block rather than reading
  it as `"3"`: a map that takes both `3` and `"3"` has two spellings for one entry,
  and only one of them survives a round trip.

  `nil` is never made into a string. A `nil` value is rejected rather than stored as
  `""`, which would turn an absent value into a present empty one. A `nil` field
  stays `nil`, an absent map rather than an empty one.

  An empty string value is allowed, as `app.kubernetes.io/part-of: ""` is in
  Kubernetes.

  ## Formats

  A qualified name is `name` or `prefix/name`, and nothing with a second `/`.

  - `name` is 1 to #{@name_max_length} characters, begins and ends with an
    alphanumeric, and may hold `-`, `_`, and `.` in between.
  - `prefix` is a DNS subdomain of at most #{@prefix_max_length} characters: dot
    separated labels of lowercase alphanumerics and `-`, each beginning and ending
    with an alphanumeric.

  A label value is an empty string, or 1 to #{@value_max_length} characters under
  the same rule as `name`.

  Lengths are counted in bytes, which both rules make equivalent to characters by
  admitting only ASCII.

  ## Length bounds

  `max_key_length` and `max_value_length` bound the whole key and the whole value,
  and apply whatever the formats are. They are the only bound a field has under
  `:any`, where a value is otherwise as large as the column will hold.

  Under a format they narrow it: the key bound covers `prefix/name` together rather
  than either part, so the shorter of the two rules is what a key has to satisfy.

  ## Reads are lenient, writes are not

  `load/3` accepts any map, so rows written before this type was in place still
  load, as do rows written before a rule was tightened. Writing one of those rows
  back is what fails, since `dump/3` holds a value to the same rules as `cast/2`.

  That holds for a field nested in an embed too, which is why the type is embedded
  as its dumped form rather than as itself.

  A row the rules reject is only a problem on the way back out, and `c:Ecto.Repo.update/2`
  dumps the fields in the changeset, so one of those rows survives an update that
  leaves the map alone. For the write that does have to touch it, either declare the
  field as this type with the rules the stored data already meets, or reach past the
  type with `c:Ecto.Repo.update_all/3`, which is also how a backfill is best written.

  ## Errors

  A rejected value fails the changeset with `validation: :string_map` and one of:

  - `"has a key that is not a string"`
  - `"has a value that is not a string"`
  - `"has a key longer than %{max_length} bytes"`
  - `"has a value longer than %{max_length} bytes for key: %{key}"`
  - `"has an invalid key: %{key}"`
  - `"has an invalid value for key: %{key}"`

  The offending key is metadata on every one of those that has a key to name,
  interpolated into the message or not. `Trogon.Ecto.LabelMap` and
  `Trogon.Ecto.AnnotationMap` report their own name as the validation instead.
  """

  use Ecto.ParameterizedType

  @typedoc "A map of strings to strings."
  @type t :: %{optional(String.t()) => String.t()}

  @typedoc "A field's key and value rules, built by Ecto from `field/3`."
  @type params :: %{
          key_format: :any | :qualified_name | :qualified_name_ignoring_case,
          value_format: :any | :label_value,
          max_key_length: pos_integer() | :infinity,
          max_value_length: pos_integer() | :infinity,
          validation: atom()
        }

  @impl Ecto.ParameterizedType
  @spec init(keyword()) :: params()
  def init(opts) do
    opts
    |> NimbleOptions.validate!(@opts_schema)
    |> Keyword.take(@own_keys)
    |> Map.new()
    |> Map.put(:validation, :string_map)
  end

  @doc false
  @spec init_preset(keyword(), keyword(), atom()) :: params()
  def init_preset(opts, forced, validation) do
    Enum.each(forced, fn {key, _value} ->
      if Keyword.has_key?(opts, key) do
        raise ArgumentError,
              "cannot set #{inspect(key)} on this type, its rules are fixed, " <>
                "use Trogon.Ecto.StringMap for a map whose rules you choose"
      end
    end)

    opts
    |> Keyword.merge(forced)
    |> init()
    |> Map.put(:validation, validation)
  end

  @impl Ecto.ParameterizedType
  @spec type(params()) :: :map
  def type(_params), do: :map

  @impl Ecto.ParameterizedType
  @spec cast(term(), params()) :: {:ok, t() | nil} | {:error, keyword()} | :error
  def cast(nil, _params), do: {:ok, nil}

  def cast(value, params) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, value}, fn pair, acc ->
      case validate_pair(pair, params) do
        :ok -> {:cont, acc}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  def cast(_value, _params), do: :error

  defp validate_pair({key, value}, params) do
    with :ok <- validate_key(key, params) do
      validate_value(key, value, params)
    end
  end

  defp validate_key(key, params) when not is_binary(key) do
    {:error, error(params, "has a key that is not a string")}
  end

  defp validate_key(key, params) do
    with :ok <- validate_key_length(key, params) do
      validate_key_format(key, params)
    end
  end

  defp validate_key_length(key, params) do
    if within_length?(key, params.max_key_length) do
      :ok
    else
      {:error,
       error(params, "has a key longer than %{max_length} bytes",
         max_length: params.max_key_length,
         key: key
       )}
    end
  end

  defp validate_key_format(key, %{key_format: :qualified_name} = params) do
    if qualified_name?(key), do: :ok, else: {:error, invalid_key(params, key)}
  end

  defp validate_key_format(key, %{key_format: :qualified_name_ignoring_case} = params) do
    if qualified_name?(String.downcase(key)), do: :ok, else: {:error, invalid_key(params, key)}
  end

  defp validate_key_format(_key, %{key_format: :any}), do: :ok

  defp invalid_key(params, key), do: error(params, "has an invalid key: %{key}", key: key)

  defp validate_value(key, value, params) when not is_binary(value) do
    {:error, error(params, "has a value that is not a string", key: key)}
  end

  defp validate_value(key, value, params) do
    with :ok <- validate_value_length(key, value, params) do
      validate_value_format(key, value, params)
    end
  end

  defp validate_value_length(key, value, params) do
    if within_length?(value, params.max_value_length) do
      :ok
    else
      {:error,
       error(params, "has a value longer than %{max_length} bytes for key: %{key}",
         max_length: params.max_value_length,
         key: key
       )}
    end
  end

  defp validate_value_format(key, value, %{value_format: :label_value} = params) do
    if label_value?(value),
      do: :ok,
      else: {:error, error(params, "has an invalid value for key: %{key}", key: key)}
  end

  defp validate_value_format(_key, _value, %{value_format: :any}), do: :ok

  defp within_length?(_value, :infinity), do: true
  defp within_length?(value, max_length), do: byte_size(value) <= max_length

  defp qualified_name?(key) do
    case String.split(key, "/") do
      [name] -> name?(name)
      [prefix, name] -> prefix?(prefix) and name?(name)
      _parts -> false
    end
  end

  defp name?(name) do
    byte_size(name) in 1..@name_max_length and Regex.match?(@name_regex, name)
  end

  defp prefix?(prefix) do
    byte_size(prefix) in 1..@prefix_max_length and Regex.match?(@prefix_regex, prefix)
  end

  defp label_value?(""), do: true

  defp label_value?(value) do
    byte_size(value) in 1..@value_max_length and Regex.match?(@name_regex, value)
  end

  defp error(params, message, metadata \\ []) do
    [message: message] ++ metadata ++ [validation: params.validation]
  end

  @impl Ecto.ParameterizedType
  @spec load(term(), (Ecto.Type.t(), term() -> {:ok, term()} | :error), params()) ::
          {:ok, map() | nil} | :error
  def load(nil, _loader, _params), do: {:ok, nil}
  def load(value, _loader, _params) when is_map(value) and not is_struct(value), do: {:ok, value}
  def load(_value, _loader, _params), do: :error

  @impl Ecto.ParameterizedType
  @spec dump(term(), (Ecto.Type.t(), term() -> {:ok, term()} | :error), params()) ::
          {:ok, t() | nil} | :error
  def dump(nil, _dumper, _params), do: {:ok, nil}

  def dump(value, _dumper, params) when is_map(value) and not is_struct(value) do
    case cast(value, params) do
      {:ok, value} -> {:ok, value}
      _error -> :error
    end
  end

  def dump(_value, _dumper, _params), do: :error

  @impl Ecto.ParameterizedType
  @spec embed_as(atom(), params()) :: :dump
  def embed_as(_format, _params), do: :dump
end

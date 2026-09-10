defmodule Trogon.Ecto.Type.Duration do
  @moduledoc """
  An `Ecto.Type` that wraps Elixir's `Duration` and persists it as an ISO 8601 string.
  """

  use Ecto.Type

  @doc """
  Returns the underlying Ecto type used to persist the value.

  The dumped representation is an ISO 8601 binary, so the declared type is `:string`
  rather than `:duration`.

  ## Examples

      iex> Trogon.Ecto.Type.Duration.type()
      :string
  """
  @impl Ecto.Type
  @spec type() :: :string
  def type, do: :string

  @doc """
  Casts a value into a `t:Duration.t/0`.

  Accepts a `Duration` struct as-is, parses an ISO 8601 binary, and treats
  `nil` as `nil`. Anything else returns `:error`.

  ## Examples

      iex> Trogon.Ecto.Type.Duration.cast(Duration.new!(second: 10))
      {:ok, Duration.new!(second: 10)}

      iex> Trogon.Ecto.Type.Duration.cast("PT10S")
      {:ok, Duration.new!(second: 10)}

      iex> Trogon.Ecto.Type.Duration.cast(nil)
      {:ok, nil}

      iex> Trogon.Ecto.Type.Duration.cast("random value")
      :error
  """
  @impl Ecto.Type
  @spec cast(term()) :: {:ok, Duration.t() | nil} | :error
  def cast(%Duration{} = value), do: {:ok, value}
  def cast(nil), do: {:ok, nil}

  def cast(value) when is_binary(value) do
    case Duration.from_iso8601(value) do
      {:ok, duration} -> {:ok, duration}
      {:error, _reason} -> :error
    end
  end

  def cast(_value), do: :error

  @doc """
  Loads a value from the database into a `t:Duration.t/0`.

  ## Examples

      iex> Trogon.Ecto.Type.Duration.load("PT10S")
      {:ok, Duration.new!(second: 10)}

      iex> Trogon.Ecto.Type.Duration.load(nil)
      {:ok, nil}

      iex> Trogon.Ecto.Type.Duration.load("random value")
      :error
  """
  @impl Ecto.Type
  @spec load(term()) :: {:ok, Duration.t() | nil} | :error
  def load(%Duration{} = value), do: {:ok, value}
  def load(nil), do: {:ok, nil}

  def load(value) when is_binary(value) do
    case Duration.from_iso8601(value) do
      {:ok, duration} -> {:ok, duration}
      {:error, _reason} -> :error
    end
  end

  def load(_value), do: :error

  @doc """
  Dumps a `t:Duration.t/0` into its ISO 8601 string representation.

  ## Examples

      iex> Trogon.Ecto.Type.Duration.dump(Duration.new!(second: 10))
      {:ok, "PT10S"}

      iex> Trogon.Ecto.Type.Duration.dump(nil)
      {:ok, nil}

      iex> Trogon.Ecto.Type.Duration.dump("random value")
      :error
  """
  @impl Ecto.Type
  @spec dump(term()) :: {:ok, String.t() | nil} | :error
  def dump(%Duration{} = value), do: {:ok, Duration.to_iso8601(value)}
  def dump(nil), do: {:ok, nil}
  def dump(_value), do: :error

  @doc """
  Returns how the value is persisted when the type is used inside an embed.

  `:dump`, so a `Duration` nested in a value object or embedded schema is persisted
  as its ISO 8601 string. The default of `:self` would keep the struct, which JSON
  encoders cannot serialize.

  ## Examples

      iex> Trogon.Ecto.Type.Duration.embed_as(:json)
      :dump
  """
  @impl Ecto.Type
  @spec embed_as(atom()) :: :dump
  def embed_as(_format), do: :dump
end

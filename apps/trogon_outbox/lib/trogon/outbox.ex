defmodule Trogon.Outbox do
  @moduledoc """
  A Postgres transactional outbox.

  Append events inside the business transaction with `append/4`, and publish them with
  `Trogon.Outbox.Relay`. Events of one source are delivered in commit order with a gapless seq.
  Install the tables with `Trogon.Outbox.Migration`.
  """

  alias Trogon.Outbox.{Event, Partition, Postgres, Publisher.Limits, Source, Writer}

  @typedoc """
  How `append/4` serializes writers of one source.

  `:counter` bumps a per-source counter row and is the default. `:advisory_lock` takes a
  transaction-scoped advisory lock and reads the previous seq from the events table, which needs
  read committed isolation and restarts at 1 once retention removes every event of a source.
  """
  @type strategy :: :counter | :advisory_lock

  @type option :: {:prefix, String.t()} | {:strategy, strategy()} | {:limits, Limits.t()}

  @doc """
  Appends payloads to a source inside the caller's transaction on `repo`.

  Raises when called outside a transaction, because an outbox write must commit or roll back with
  the business write. Writers of the same source wait for each other until commit; writers of
  different sources do not.

  Every payload is validated against `:limits` before anything is written, so a payload the
  publisher could never deliver never commits: only the environment, never a bad event, is allowed
  to stall a partition. `:limits` defaults to `Trogon.Outbox.Publisher.Limits.default/0`; pass the
  same `Limits.t()` the configured publisher builds from its own options with its `limits/1`
  callback, so the two agree on one `max_payload_size`.
  """
  @spec append(Ecto.Repo.t(), Source.t() | String.t(), binary() | [binary()], [option()]) :: {:ok, [Event.t()]}
  def append(repo, source, payloads, opts \\ []) do
    source = to_source(source)
    payloads = to_payloads(payloads)
    prefix = Keyword.get(opts, :prefix, "public")
    strategy = Keyword.get(opts, :strategy, :counter)
    limits = Keyword.get(opts, :limits, Limits.default())

    unless repo.in_transaction?() do
      raise ArgumentError, "Trogon.Outbox.append/4 must run inside a transaction on #{inspect(repo)}"
    end

    validate_payloads!(payloads, limits)

    case payloads do
      [] -> {:ok, []}
      payloads -> {:ok, Writer.append(repo, source, payloads, prefix, strategy)}
    end
  end

  defp validate_payloads!(payloads, limits) do
    Enum.each(payloads, fn payload ->
      case Limits.validate_payload(limits, payload) do
        :ok ->
          :ok

        {:error, {:payload_too_large, size, max}} ->
          raise ArgumentError,
                "a payload of #{size} bytes exceeds the publisher's max_payload_size of #{max} bytes"
      end
    end)
  end

  @doc "The number of partitions fixed when the outbox was installed."
  @spec partition_count(Ecto.Repo.t(), [option()]) :: pos_integer()
  def partition_count(repo, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "public")

    %Postgrex.Result{rows: [[count]]} =
      Postgres.query!(repo, "SELECT #{Postgres.name(prefix, "outbox_partition_count")}()", [])

    count
  end

  @doc "The partition a source maps to."
  @spec partition_of(Ecto.Repo.t(), Source.t() | String.t(), [option()]) :: Partition.t()
  def partition_of(repo, source, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "public")
    source = to_source(source)

    %Postgrex.Result{rows: [[partition]]} =
      Postgres.query!(repo, "SELECT #{Postgres.name(prefix, "outbox_partition")}($1)", [source.value])

    Partition.new!(partition)
  end

  defp to_source(%Source{} = source), do: source
  defp to_source(source), do: Source.new!(source)

  defp to_payloads(payload) when is_binary(payload), do: [payload]

  defp to_payloads(payloads) when is_list(payloads) do
    if Enum.all?(payloads, &is_binary/1),
      do: payloads,
      else: raise(ArgumentError, "payloads must be binaries, got: #{inspect(payloads)}")
  end
end

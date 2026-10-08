defmodule Trogon.Outbox.TestSupport.SkewedClockRepo do
  @moduledoc """
  Stands in for `Trogon.Outbox.TestRepo` on an Oban instance that should
  behave like a node whose clock is off. Every timestamp the instance sends to
  the database, in queries, rows, and changesets alike, is shifted by the
  configured skew before it reaches `Trogon.Outbox.TestRepo`, so Oban's own
  code runs unchanged while it reads its node clock wrong. Timestamps the
  database assigns itself, such as column defaults, keep the database clock,
  and a timestamp the instance read back from the database, such as a job's
  `attempted_at` used to match its ack, is sent back unshifted, as a real node
  would.
  """

  alias Trogon.Outbox.TestRepo

  @with_opts [
    aggregate: 3,
    all: 2,
    delete: 2,
    delete_all: 2,
    exists?: 2,
    get: 3,
    insert: 2,
    insert_all: 3,
    one: 2,
    query: 3,
    query!: 3,
    stream: 2,
    transaction: 2,
    update: 2,
    update_all: 3
  ]

  @spec skew!(integer()) :: :ok
  def skew!(seconds) do
    if :ets.whereis(__MODULE__) == :undefined do
      :ets.new(__MODULE__, [:set, :public, :named_table])
    end

    :persistent_term.put(__MODULE__, seconds)
  end

  @spec config() :: keyword()
  def config, do: TestRepo.config()

  @spec get_dynamic_repo() :: atom() | pid()
  def get_dynamic_repo, do: TestRepo.get_dynamic_repo()

  @spec put_dynamic_repo(atom() | pid()) :: atom() | pid()
  def put_dynamic_repo(repo), do: TestRepo.put_dynamic_repo(repo)

  @spec in_transaction?() :: boolean()
  def in_transaction?, do: TestRepo.in_transaction?()

  @spec default_options(atom()) :: keyword()
  def default_options(operation), do: TestRepo.default_options(operation)

  for {fun, arity} <- @with_opts do
    args = Macro.generate_arguments(arity - 1, __MODULE__)

    def unquote(fun)(unquote_splicing(args), opts \\ []) do
      result = apply(TestRepo, unquote(fun), shift([unquote_splicing(args)]) ++ [opts])
      remember(result)
      result
    end
  end

  defp shift(term), do: shift(term, :persistent_term.get(__MODULE__, 0))

  defp shift(%DateTime{} = datetime, seconds) do
    if read_back?(datetime), do: datetime, else: DateTime.add(datetime, seconds, :second)
  end

  defp shift(%NaiveDateTime{} = datetime, seconds), do: NaiveDateTime.add(datetime, seconds, :second)
  defp shift(%{} = map, seconds), do: :maps.map(fn _key, value -> shift(value, seconds) end, map)
  defp shift([head | tail], seconds), do: [shift(head, seconds) | shift(tail, seconds)]

  defp shift(tuple, seconds) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> shift(seconds) |> List.to_tuple()

  defp shift(term, _seconds), do: term

  defp read_back?(datetime) do
    :ets.whereis(__MODULE__) != :undefined and :ets.member(__MODULE__, DateTime.to_unix(datetime, :microsecond))
  end

  defp remember(%DateTime{} = datetime) do
    if :ets.whereis(__MODULE__) != :undefined do
      :ets.insert(__MODULE__, {DateTime.to_unix(datetime, :microsecond)})
    end
  end

  defp remember(%{} = map), do: map |> Map.values() |> Enum.each(&remember/1)
  defp remember(list) when is_list(list), do: Enum.each(list, &remember/1)
  defp remember(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> remember()
  defp remember(_term), do: :ok
end

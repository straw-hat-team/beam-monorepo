defmodule Trogon.Credo.NonDeterministicCalls do
  @moduledoc false

  # The calls that draw wall clock time, randomness, or an id from a source the
  # caller does not control, given as `Trogon.Credo.Check.Warning.ForbiddenFunctionCall`
  # `calls:` entries, without messages, since what to do instead depends on which
  # check reports them.
  def calls do
    [
      {DateTime, :utc_now},
      {DateTime, :now},
      {DateTime, :now!},
      {Date, :utc_today},
      {Time, :utc_now},
      {NaiveDateTime, :utc_now},
      {NaiveDateTime, :local_now},
      {System, :system_time},
      {System, :os_time},
      {System, :monotonic_time},
      {System, :unique_integer},
      {Enum, :random},
      {Enum, :shuffle},
      {Enum, :take_random},
      {Kernel, :make_ref},
      :rand,
      :random,
      {:crypto, :strong_rand_bytes},
      {:os, :system_time},
      {:os, :timestamp},
      {:erlang, :system_time},
      {:erlang, :monotonic_time},
      {:erlang, :unique_integer},
      {:erlang, :now},
      {:erlang, :timestamp},
      {Ecto.UUID, :generate},
      {Ecto.UUID, :bingenerate},
      Uniq.UUID,
      UUID,
      Nanoid
    ]
  end
end

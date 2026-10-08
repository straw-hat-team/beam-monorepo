defmodule Trogon.Outbox.LockNamespace do
  @moduledoc """
  Advisory lock namespaces used by the outbox.

  The outbox only uses the two-integer form `pg_advisory_lock(classid, objid)` with one of these
  fixed classids. Postgres tags two-integer locks with `objsubid = 2` and single-bigint locks,
  such as those taken by job libraries for unique jobs, with `objsubid = 1`, so the two forms
  never collide even when their bits are equal.
  """

  @spec writer() :: integer()
  def writer, do: 0x544F7772

  @spec relay() :: integer()
  def relay, do: 0x544F726C
end

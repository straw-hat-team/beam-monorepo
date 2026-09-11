defmodule Trogon.Ecto.Query do
  @moduledoc """
  Query macros that push computation into the database.

  Import alongside `Ecto.Query`:

      import Ecto.Query
      import Trogon.Ecto.Query

  These macros expand to `Ecto.Query.API.fragment/1` calls, so they can only be
  used inside a query expression.
  """

  @doc """
  Averages a field and rounds the result to `precision` decimal places in the
  database.

      from(m in Measurement,
        group_by: m.sensor_id,
        select: %{sensor_id: m.sensor_id, average: rounded_avg(m.value, 2)}
      )

  The average is cast to `numeric` before being rounded, because PostgreSQL only
  defines two argument `ROUND` for `numeric`, while averaging a `:float` column
  gives `double precision`. Without the cast the query fails at run time with
  `function round(double precision, integer) does not exist`.

  The result is a `numeric`, so it loads as a `Decimal` whatever the field's own
  type is. A group whose values are all `NULL` averages to `NULL`, which loads as
  `nil` rather than as a zero.
  """
  defmacro rounded_avg(field, precision) do
    quote do
      fragment("ROUND(CAST(AVG(?) AS numeric), ?)", unquote(field), unquote(precision))
    end
  end
end

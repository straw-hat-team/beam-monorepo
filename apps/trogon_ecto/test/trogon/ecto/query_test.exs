defmodule Trogon.Ecto.QueryTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Trogon.Ecto.Query

  describe "rounded_avg/2" do
    test "builds the fragment around the field and the precision" do
      query =
        from(m in "measurements",
          group_by: m.sensor_id,
          select: %{sensor_id: m.sensor_id, average: rounded_avg(m.value, 2)}
        )

      assert inspect(query) =~ ~s|fragment("ROUND(CAST(AVG(?) AS numeric), ?)", m0.value, 2)|
    end

    test "takes a precision from a bound variable" do
      precision = 3
      query = from(m in "measurements", select: rounded_avg(m.value, ^precision))

      assert inspect(query) =~ ~s|fragment("ROUND(CAST(AVG(?) AS numeric), ?)", m0.value, ^3)|
    end

    test "can be used outside of a select" do
      query = from(m in "measurements", group_by: m.sensor_id, having: rounded_avg(m.value, 1) > 4.5)

      assert inspect(query) =~ ~s|fragment("ROUND(CAST(AVG(?) AS numeric), ?)", m0.value, 1) > 4.5|
    end
  end
end

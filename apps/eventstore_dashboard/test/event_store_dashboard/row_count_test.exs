defmodule EventStoreDashboard.RowCountTest do
  use ExUnit.Case, async: true

  alias EventStoreDashboard.RowCount

  describe "total_pages/2" do
    test "an empty count has no pages" do
      assert RowCount.total_pages(RowCount.zero(), 50) == 0
    end

    test "a partial page still counts as a page" do
      assert RowCount.total_pages(RowCount.exact(1), 50) == 1
      assert RowCount.total_pages(RowCount.exact(50), 50) == 1
      assert RowCount.total_pages(RowCount.exact(51), 50) == 2
    end

    test "an estimate pages the same way as an exact count" do
      assert RowCount.total_pages(RowCount.estimated(10_027_356), 50) == 200_548
    end
  end

  describe "String.Chars" do
    test "an exact count renders as a plain number" do
      assert to_string(RowCount.exact(42)) == "42"
    end

    test "an estimate is marked as approximate" do
      assert to_string(RowCount.estimated(10_027_356)) == "~10027356"
    end
  end

  describe "estimated/1" do
    test "rejects a non-positive value, which never carries usable statistics" do
      assert_raise FunctionClauseError, fn -> RowCount.estimated(0) end
      assert_raise FunctionClauseError, fn -> RowCount.estimated(-1) end
    end
  end
end

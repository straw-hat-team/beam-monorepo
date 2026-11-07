defmodule EventStoreDashboard.Components.PaginationTest do
  use ExUnit.Case, async: true

  alias EventStoreDashboard.Components.Pagination

  describe "total_pages/4" do
    test "keeps a next page reachable when the estimate undercounts" do
      assert Pagination.total_pages(50, 50, 1, 51) == 2
      assert Pagination.total_pages(50, 50, 2, 51) == 3
    end

    test "uses the estimate when it is ahead of the current page" do
      assert Pagination.total_pages(500, 50, 1, 51) == 10
    end

    test "ends at the current page when no extra row came back" do
      assert Pagination.total_pages(500, 50, 3, 20) == 3
      assert Pagination.total_pages(50, 50, 3, 20) == 3
    end

    test "falls back to the estimate for an empty page" do
      assert Pagination.total_pages(0, 50, 1, 0) == 0
      assert Pagination.total_pages(500, 50, 20, 0) == 10
    end
  end
end

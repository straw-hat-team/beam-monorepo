defmodule EventStoreDashboard.ParamsTest do
  use ExUnit.Case, async: true

  alias EventStoreDashboard.Params
  alias EventStoreDashboard.Test.{DashboardRouter, Endpoint}
  alias Phoenix.LiveDashboard.PageBuilder

  setup do
    Code.ensure_loaded!(DashboardRouter)
    :ok
  end

  @table_params %{"search" => "adelr:fan_", "limit" => "100", "sort_by" => "stream_uuid", "sort_dir" => "desc"}

  describe "to_live_dashboard_path/3" do
    test "drops the table params when the target tab differs from the current one" do
      page = page(Map.put(@table_params, "nav", "streams"))

      path = Params.to_live_dashboard_path(socket(), page, %Params{nav: "events", stream: "adelr:fan_1"})

      query = query(path)
      assert query["nav"] == "events"
      assert query["stream"] == "adelr:fan_1"
      refute Map.has_key?(query, "search")
      refute Map.has_key?(query, "limit")
      refute Map.has_key?(query, "sort_by")
      refute Map.has_key?(query, "sort_dir")
    end

    test "keeps the table params when navigating within the same tab" do
      page = page(Map.put(@table_params, "nav", "streams"))

      path = Params.to_live_dashboard_path(socket(), page, %Params{nav: "streams", stream_modal: "adelr:fan_1"})

      query = query(path)
      assert query["stream_modal"] == "adelr:fan_1"
      assert query["search"] == "adelr:fan_"
      assert query["limit"] == "100"
      assert query["sort_by"] == "stream_uuid"
      assert query["sort_dir"] == "desc"
    end

    test "treats a missing nav as the streams tab on both sides" do
      page = page(@table_params)

      path = Params.to_live_dashboard_path(socket(), page, %Params{stream_modal: "adelr:fan_1"})

      assert query(path)["search"] == "adelr:fan_"
    end

    test "drops the table params when leaving the implicit streams tab" do
      page = page(@table_params)

      path = Params.to_live_dashboard_path(socket(), page, %Params{nav: "subscriptions"})

      query = query(path)
      assert query["nav"] == "subscriptions"
      refute Map.has_key?(query, "search")
    end
  end

  defp socket do
    %Phoenix.LiveView.Socket{endpoint: Endpoint, router: DashboardRouter}
  end

  defp page(params) do
    %PageBuilder{route: :event_store, node: node(), params: params}
  end

  defp query(path) do
    URI.decode_query(URI.parse(path).query)
  end
end

defmodule Trogon.Telemetry.DocsTest do
  use ExUnit.Case, async: true

  alias Trogon.Telemetry.Docs
  alias Trogon.Telemetry.TestSupport.DeliverLogStream
  alias Trogon.Telemetry.TestSupport.EctoQuery
  alias Trogon.Telemetry.TestSupport.LogStreamDelivery
  alias Trogon.Telemetry.TestSupport.Uninstrumented

  test "appends the generated section to the moduledoc the module wrote" do
    doc = moduledoc(LogStreamDelivery)

    assert doc =~ "Emitted once per delivery attempt to a log stream destination."
    assert doc =~ "`[:trogon_telemetry_test, :hooks, :log_stream_delivery]`"
    assert doc =~ "| `count` | integer | `1` | `counter` | delivery | Always 1. Sum it for delivery volume. |"
    assert doc =~ "| `result` | `:ok` \\| `:error` | yes |  |"
  end

  test "documents the three events of a span and the fields telemetry fills in" do
    doc = moduledoc(DeliverLogStream)

    assert doc =~
             "- `[:trogon_telemetry_test, :hooks, :deliver_log_stream, :start]` as " <>
               "`Trogon.Telemetry.TestSupport.DeliverLogStream.Start`"

    assert doc =~
             "- `[:trogon_telemetry_test, :hooks, :deliver_log_stream, :stop]` as " <>
               "`Trogon.Telemetry.TestSupport.DeliverLogStream.Stop`"

    assert doc =~
             "- `[:trogon_telemetry_test, :hooks, :deliver_log_stream, :exception]` as " <>
               "`Trogon.Telemetry.TestSupport.DeliverLogStream.Exception`"

    assert doc =~
             "| `duration` | integer | `stop`, `exception` | `histogram` | native as millisecond | " <>
               "Filled in by `Trogon.Telemetry`. |"

    assert doc =~
             "| `bytes_sent` | integer | `stop` | `histogram` | byte | Payload size handed to the destination. |"
  end

  test "lists the metrics a declaration derives" do
    assert moduledoc(LogStreamDelivery) =~
             "- `trogon_telemetry_test.hooks.log_stream_delivery.count` as a sum, broken down by " <>
               "`project_id`, `result`"
  end

  test "lists one duration metric per span phase carrying it" do
    doc = moduledoc(DeliverLogStream)

    assert doc =~
             "- `trogon_telemetry_test.hooks.deliver_log_stream.stop.duration` as a distribution, " <>
               "broken down by `project_id`, `result`"

    assert doc =~
             "- `trogon_telemetry_test.hooks.deliver_log_stream.exception.duration` as a distribution, " <>
               "broken down by `project_id`"
  end

  test "says an observation is emitted elsewhere and does not prefix its name" do
    doc = moduledoc(EctoQuery)

    assert doc =~ "`[:some_other_app, :repo, :query]`"
    assert doc =~ "Emitted elsewhere."
    assert doc =~ "| `total_time` | integer | `histogram`, buckets `[10, 50, 100]` | native as millisecond |"
  end

  test "leaves the metric columns out when nothing declares one" do
    refute moduledoc(Uninstrumented) =~ "Metric"
    assert moduledoc(Uninstrumented) =~ "| `count` | integer | `nil` |  |"
  end

  test "renders a definition on demand" do
    assert Docs.render(LogStreamDelivery.__telemetry__()) =~ "## Telemetry"
  end

  defp moduledoc(module) do
    {:docs_v1, _annotation, _language, _format, %{"en" => doc}, _metadata, _docs} = Code.fetch_docs(module)
    doc
  end
end

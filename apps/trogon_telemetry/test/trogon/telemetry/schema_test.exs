defmodule Trogon.Telemetry.SchemaTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  describe "measurements/1" do
    test "rejects a type that is not numeric" do
      assert_declaring(~r/must be numeric/, """
      measurements do
        field :name, :string
      end
      """)
    end

    test "rejects a tag" do
      assert_declaring(~r/cannot be tagged, only attributes can/, """
      measurements do
        field :count, :integer, tag: true
      end
      """)
    end
  end

  describe "attributes/1" do
    test "rejects an unknown type" do
      assert_declaring(~r/unknown type/, """
      attributes do
        field :result, :strng
      end
      """)
    end

    test "rejects a duplicated field" do
      assert_declaring(~r/is already declared in attributes/, """
      attributes do
        field :result, :atom
        field :result, :atom
      end
      """)
    end

    test "rejects a phase on an event" do
      assert_declaring(~r/cannot declare a phase, only spans have phases/, """
      attributes do
        field :result, :atom, phase: :stop
      end
      """)
    end
  end

  describe "field/3" do
    test "must be declared inside a section" do
      assert_declaring(~r/must be called inside a measurements\/1 or attributes\/1 block/, """
      field :result, :atom
      """)
    end
  end

  describe "span declarations" do
    test "reject a reserved attribute name" do
      assert_raise ArgumentError, ~r/:duration is reserved by span measurements/, fn ->
        compile("""
        defmodule Trogon.Telemetry.SchemaTest.ReservedSpan do
          use Trogon.Telemetry.Span

          span [:a, :b] do
            measurements do
              field :duration, :integer
            end
          end
        end
        """)
      end
    end

    test "carry the phases telemetry fills in" do
      assert_raise ArgumentError, ~r/cannot declare a phase, it is always carried by the stop event/, fn ->
        compile("""
        defmodule Trogon.Telemetry.SchemaTest.PhasedMeasurement do
          use Trogon.Telemetry.Span

          span [:a, :b] do
            measurements do
              field :bytes_sent, :integer, phase: :stop
            end
          end
        end
        """)
      end
    end
  end

  describe "metric declarations" do
    test "reject an unknown metric" do
      assert_declaring(~r/unknown metric :summary for measurement :count/, """
      measurements do
        field :count, :integer, metric: :summary
      end
      """)
    end

    test "reject an instrument option with nothing to apply it to" do
      assert_declaring(~r/:count declares :unit without a :metric to apply it to/, """
      measurements do
        field :count, :integer, unit: :delivery
      end
      """)
    end

    test "reject buckets on anything but a histogram" do
      assert_declaring(~r/:count declares :buckets, which only a :histogram takes/, """
      measurements do
        field :count, :integer, metric: :counter, buckets: [1, 2]
      end
      """)
    end

    test "reject buckets that are not numbers" do
      assert_declaring(~r/:buckets must be a non-empty list of numbers/, """
      measurements do
        field :count, :integer, metric: :histogram, buckets: [:small]
      end
      """)
    end

    test "reject a metric on an attribute" do
      assert_declaring(~r/attribute :result cannot declare a :metric, only measurements can/, """
      attributes do
        field :result, :atom, metric: :counter
      end
      """)
    end

    test "reject a breakdown by something that is not a tag" do
      assert_declaring(~r/:count breaks down by \[:result\], which is not declared with tag: true/, """
      measurements do
        field :count, :integer, metric: :counter, tags: [:result]
      end

      attributes do
        field :result, :atom
      end
      """)
    end

    test "reject a span duration that is neither options nor false" do
      assert_raise ArgumentError, ~r/:duration must be a keyword list of metric options or false/, fn ->
        compile("""
        defmodule Trogon.Telemetry.SchemaTest.BadDuration do
          use Trogon.Telemetry.Span

          span [:a, :b], duration: :histogram do
            measurements do
            end
          end
        end
        """)
      end
    end
  end

  describe "observations" do
    test "reject a default" do
      assert_raise ArgumentError,
                   ~r/:count cannot declare a default, an observation describes an event emitted elsewhere/,
                   fn ->
                     compile("""
                     defmodule Trogon.Telemetry.SchemaTest.DefaultedObservation do
                       use Trogon.Telemetry.Observation

                       observe [:a, :b] do
                         measurements do
                           field :count, :integer, default: 1
                         end
                       end
                     end
                     """)
                   end
    end
  end

  test "an event module must declare an event" do
    assert_raise ArgumentError, ~r/without calling event\/2/, fn ->
      compile("""
      defmodule Trogon.Telemetry.SchemaTest.Empty do
        use Trogon.Telemetry.Event
      end
      """)
    end
  end

  defp assert_declaring(message, body) do
    assert_raise ArgumentError, message, fn ->
      compile("""
      defmodule :"Elixir.Trogon.Telemetry.SchemaTest.Generated#{System.unique_integer([:positive])}" do
        use Trogon.Telemetry.Event

        event [:a, :b] do
          #{body}
        end
      end
      """)
    end
  end

  defp compile(source) do
    capture_io(:stderr, fn -> Code.compile_string(source) end)
  end
end

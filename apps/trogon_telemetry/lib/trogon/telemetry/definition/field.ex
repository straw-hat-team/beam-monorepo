defmodule Trogon.Telemetry.Definition.Field do
  @moduledoc """
  A single field declared inside a `measurements/1` or `attributes/1` block.
  """

  alias Trogon.Telemetry.Instrument

  @typedoc """
  The events a field is carried by.

  Plain events only ever emit `:event`. Spans emit `:start`, `:stop` and `:exception`, and not every
  field is present in all three.
  """
  @type phase :: :event | :start | :stop | :exception

  @type t :: %__MODULE__{
          name: atom(),
          type: Trogon.Telemetry.Type.t(),
          default: term(),
          doc: String.t() | nil,
          tag: boolean(),
          phases: [phase(), ...],
          reserved: boolean(),
          authored: boolean(),
          instrument: Instrument.t() | nil
        }

  @enforce_keys [:name, :type, :phases]
  defstruct [
    :name,
    :type,
    :default,
    :doc,
    :phases,
    :instrument,
    tag: false,
    reserved: false,
    authored: true
  ]
end

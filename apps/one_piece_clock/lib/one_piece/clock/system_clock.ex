defmodule OnePiece.Clock.SystemClock do
  @moduledoc """
  Implements the Clock Behavior using the System clock.
  """

  @behaviour OnePiece.Clock

  @impl OnePiece.Clock
  def utc_now do
    DateTime.utc_now()
  end
end

defmodule OnePiece.Commanded.StatelessLifespanTest do
  use ExUnit.Case, async: true
  alias TestSupport.{DepositAccountOpened, MyCommandOne}
  doctest OnePiece.Commanded.Aggregate.StatelessLifespan
end

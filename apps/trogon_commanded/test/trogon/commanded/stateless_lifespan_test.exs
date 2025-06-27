defmodule Trogon.Commanded.StatelessLifespanTest do
  use ExUnit.Case, async: true
  alias TestSupport.{DepositAccountOpened, MyCommandOne}
  doctest Trogon.Commanded.Aggregate.StatelessLifespan
end

defmodule PepegTest do
  use ExUnit.Case, async: true

  test "the truth" do
    assert MyApp.Oban.config() |> dbg()
  end
end

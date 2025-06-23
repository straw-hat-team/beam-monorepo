defmodule Trogon.ResultTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  require Logger

  alias Trogon.Result

  doctest Result

  describe "tap_ok/2" do
    test "calls the callback when a ok result is pass" do
      assert capture_log(fn ->
               42
               |> Result.ok()
               |> Result.tap_ok(&success_logger/1)
             end) =~ "success 42"
    end

    test "ignores the callback when a err result is pass" do
      assert capture_log(fn ->
               "ooops"
               |> Result.err()
               |> Result.tap_ok(&success_logger/1)
             end) == ""
    end
  end

  describe "tap_err/2" do
    test "calls the callback when a err result is pass" do
      assert capture_log(fn ->
               "ooops"
               |> Result.err()
               |> Result.tap_err(&failure_logger/1)
             end) =~ "failure ooops"
    end

    test "ignores the callback when a err result is pass" do
      assert capture_log(fn ->
               42
               |> Result.ok()
               |> Result.tap_err(&failure_logger/1)
             end) == ""
    end
  end

  defp success_logger(x) do
    Logger.notice("success #{x}")
  end

  defp failure_logger(x) do
    Logger.error("failure #{x}")
  end
end

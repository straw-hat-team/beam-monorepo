defmodule Trogon.Credo.TestFile do
  @moduledoc false

  # A test file is one ExUnit runs, a filename ending in `_test.exs`, or one under
  # a `test/support` directory anywhere in its path, which exists to build
  # fixtures for those tests.
  @spec test_file?(String.t()) :: boolean()
  def test_file?(filename) do
    String.ends_with?(filename, "_test.exs") or filename |> Path.split() |> under_test_support?()
  end

  defp under_test_support?(["test", "support" | _rest]), do: true
  defp under_test_support?([_segment | rest]), do: under_test_support?(rest)
  defp under_test_support?([]), do: false
end

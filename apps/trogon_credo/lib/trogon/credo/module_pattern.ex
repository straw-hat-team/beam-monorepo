defmodule Trogon.Credo.ModulePattern do
  @moduledoc false

  alias Trogon.Credo.ModuleName

  # A regex matching the fully qualified module names a pattern names, anchored at
  # both ends, or `:error` for anything that is not a pattern.
  #
  # Everything other than a wildcard is literal, including a character that would
  # otherwise be regex syntax. A `*` matches any run of characters within a single
  # segment, and a `**` any run that may cross a `.`. A plain module name, given as
  # an atom, names only that module.
  #
  # A caller raises its own error for `:error`, so the wording names the parameter
  # the pattern was written in.
  def compile(pattern) when is_binary(pattern), do: {:ok, to_regex(pattern)}

  def compile(pattern) when is_atom(pattern) do
    {:ok, pattern |> ModuleName.full() |> to_regex()}
  end

  def compile(_pattern), do: :error

  # The compiled pattern, for a caller that has already made sure what it holds is
  # one.
  def compile!(pattern) do
    case compile(pattern) do
      {:ok, regex} ->
        regex

      :error ->
        raise ArgumentError,
              "invalid module pattern #{inspect(pattern)}: expected a module name pattern as a string, or a plain module name"
    end
  end

  # The regex source a pattern compiles to, without the anchors, so that a caller
  # can build a larger expression around it.
  def source(pattern) when is_binary(pattern) do
    pattern |> String.split(".") |> segments_source()
  end

  # The name an Erlang module matched by a pattern is written under, so that a
  # message names the module the way the source does.
  def display(<<first, _rest::binary>> = module) when first in ?a..?z, do: ":" <> module
  def display(module), do: module

  defp to_regex(pattern) do
    Regex.compile!("^#{source(pattern)}$")
  end

  # A `**` standing as a whole segment is the one wildcard that can match no
  # segment at all, so that a pattern naming an optional level of nesting covers
  # the name without it. A trailing one still needs a segment, which is what
  # keeps `Acme.Repo.**` from naming `Acme.Repo`.
  defp segments_source(["**"]), do: ".+"
  defp segments_source(["**" | rest]), do: "(?:[^.]+\\.)*" <> segments_source(rest)
  defp segments_source([segment]), do: segment_source(segment)
  defp segments_source([segment, "**"]), do: segment_source(segment) <> "(?:\\.[^.]+)+"

  defp segments_source([segment, "**" | rest]) do
    segment_source(segment) <> "(?:\\.[^.]+)*\\." <> segments_source(rest)
  end

  defp segments_source([segment | rest]) do
    segment_source(segment) <> "\\." <> segments_source(rest)
  end

  defp segment_source(segment) do
    segment
    |> Regex.escape()
    |> String.replace("\\*\\*", ".+")
    |> String.replace("\\*", "[^.]+")
  end
end

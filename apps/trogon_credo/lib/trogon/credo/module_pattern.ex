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

  # A regex compiled from a pattern whose parenthesized prefix names an owning
  # namespace, the remainder naming what that namespace keeps to itself. The
  # regex captures the owner, matched against a fully qualified module name,
  # anchored at both ends. A pattern that is only the parenthesized prefix makes
  # the namespace private to itself, the module and everything under it.
  # `:error` for anything that is not such a pattern, including a plain module
  # name given as an atom, since an owner pattern is always written as a string.
  def compile_owner_pattern(pattern) when is_binary(pattern) do
    case Regex.run(~r/^\(([^()]+)\)(.*)$/, pattern) do
      [_full, owner, ""] ->
        {:ok, Regex.compile!("^(#{source(owner)})(?:\\..+)?$")}

      [_full, owner, "." <> _ = private] ->
        {:ok, Regex.compile!("^(#{source(owner)})#{source(private)}$")}

      _other ->
        :error
    end
  end

  def compile_owner_pattern(_pattern), do: :error

  # The owner an owner pattern's compiled regex binds a module to, or `nil`
  # when the module does not match the pattern at all.
  def find_owner(module, regex) do
    case Regex.run(regex, module) do
      [_full, owner] -> owner
      nil -> nil
    end
  end

  # Whether the given module, read as a file's own outermost module name, sits
  # inside the given owning namespace, the namespace itself or anything under
  # it. A file whose own module cannot be read is always treated as inside,
  # since the check that asks has no namespace to compare the owner against.
  def owner_includes?(nil, _owner), do: true

  def owner_includes?(own_module, owner) do
    own_module == owner or String.starts_with?(own_module, owner <> ".")
  end

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

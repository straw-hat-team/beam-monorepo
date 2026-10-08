defmodule Trogon.Credo.CheckDelegate do
  @moduledoc false

  # Runs a generic check on behalf of a dedicated one, so a domain rule reuses the
  # generic implementation without sharing its module name.
  #
  # Credo matches `credo:disable-for-*` comments, `mix credo explain`, and the
  # `--only`/`--ignore` switches against an issue's `check` field, so every issue is
  # retargeted at the dedicated check. Category, priority, and exit status are left
  # as the generic check computed them: the dedicated check passes its own params
  # through, so a `priority:` or `category:` set on it still applies, and every
  # dedicated check shares its generic check's category, so the defaults agree too.
  def run(source_file, params, check, generic, generic_params) do
    source_file
    |> generic.run(Keyword.merge(params, generic_params))
    |> Enum.map(&%{&1 | check: check})
  end
end

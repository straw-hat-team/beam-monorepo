defmodule Trogon.Credo.Check.Commanded.AggregateApplyCall do
  alias Trogon.Credo.Check.Commanded.AggregateStateConstruction

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    run_on_all: true,
    param_defaults: AggregateStateConstruction.param_defaults(),
    explanations: AggregateStateConstruction.explanations()

  @moduledoc """
  Deprecated. Renamed to
  `Trogon.Credo.Check.Commanded.AggregateStateConstruction`, since this check grew
  to cover more than a direct call to `apply/2`: a constructor call, a struct
  literal, the struct update syntax, and a call to `struct/2` or `struct!/2` all
  build an aggregate's state the same way a direct `apply/2` call does, so the
  name no longer fit.

  This module still runs the same check under its old name, so a project that
  configured `Trogon.Credo.Check.Commanded.AggregateApplyCall` keeps working
  unchanged, including any params it set. New configuration should use
  `Trogon.Credo.Check.Commanded.AggregateStateConstruction` directly.
  """

  @doc false
  @impl true
  @deprecated "Use Trogon.Credo.Check.Commanded.AggregateStateConstruction instead"
  def run_on_all_source_files(exec, source_files, params) do
    # Report as this module, not AggregateStateConstruction, so an inline
    # `credo:disable` comment naming the old check still matches its issues.
    AggregateStateConstruction.run_on_all_source_files(
      exec,
      source_files,
      Keyword.put_new(params, :reporting_check, __MODULE__)
    )
  end
end

defmodule Trogon.Credo.PluginSupport.EnableChecks do
  @moduledoc false

  use Credo.Execution.Task

  alias Trogon.Credo.PluginSupport

  @impl true
  def call(%Execution{checks: %{enabled: enabled} = checks} = exec, opts) when is_list(enabled) do
    configured = MapSet.new(enabled, &elem(&1, 0))
    added = opts |> Keyword.fetch!(:checks) |> PluginSupport.reject_listed(configured)

    %{exec | checks: %{checks | enabled: enabled ++ added}}
  end

  def call(exec, _opts), do: exec
end

defmodule Trogon.Credo.PluginSupport.EnableChecks do
  @moduledoc false

  use Credo.Execution.Task

  @impl true
  def call(%Execution{checks: %{enabled: enabled} = checks} = exec, opts) when is_list(enabled) do
    configured = MapSet.new(enabled, &elem(&1, 0))
    added = Enum.reject(Keyword.fetch!(opts, :checks), fn {check, _params} -> check in configured end)

    %{exec | checks: %{checks | enabled: enabled ++ added}}
  end

  def call(exec, _opts), do: exec
end

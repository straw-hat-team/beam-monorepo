defmodule TestSupport.MyCommand do
  @moduledoc false

  defstruct [:name, :value]

  defimpl ElixirStdlib.Into do
    def into(from, TestSupport.MyEvent) do
      %TestSupport.MyEvent{name: from.name, value: from.value}
    end
  end
end

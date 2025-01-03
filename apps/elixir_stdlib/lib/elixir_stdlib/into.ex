defprotocol ElixirStdlib.Into do
  @moduledoc """
  Protocol for transforming data between different data structures, inspired by Rust's `Into` trait.

  This protocol allows types to define how they can be converted into other types in a consistent way.
  The implementing type is the target type that other values will be converted into.
  """

  @doc """
  Transforms the given value into the target data structure.

  ## Parameters

    * `from` - The source value to convert from
    * `to` - The atom representing the target data structure to convert into.

  ## Examples

  Convert a map set to a list.

      defmodule TestSupport.MyCommand do
        defstruct [:name, :value]
      end

      defmodule TestSupport.MyEvent do
        defstruct [:name, :value]
      end

      defimpl ElixirStdlib.Into, for: MyCommand do
        def into(my_command, MyEvent) do
          %MyEvent{name: my_command.name, value: my_command.value}
        end
      end

      ElixirStdlib.Into.into(%MyCommand{name: "test", value: 1}, MyEvent)
      #=> %MyEvent{name: "test", value: 1}
  """
  @spec into(any(), atom()) :: any()
  def into(from, to)
end

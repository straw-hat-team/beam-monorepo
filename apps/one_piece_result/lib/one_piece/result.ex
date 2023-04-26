defmodule OnePiece.Result do
  @moduledoc """
  Handles `t:t/0` responses. Inspired by Rust `std::result::Result` package.
  """

  alias OnePiece.Result.ErrUnwrapError
  alias OnePiece.Result.OkUnwrapError
  alias OnePiece.Result.ExpectedError

  @typedoc """
  An Ok result.
  """
  @type ok :: {:ok, any}

  @typedoc """
  An Error result.
  """
  @type err :: {:error, any}

  @typedoc """
  An Result Tuple.
  """
  @type t :: ok() | err()

  @doc """
  Wraps a value into an `t:ok/0` result.

      iex> OnePiece.Result.ok(42)
      {:ok, 42}
  """
  @spec ok(value :: any) :: ok
  def ok(value), do: {:ok, value}

  @doc """
  Wraps a value into an `t:err/0` result.

      iex> OnePiece.Result.err("oops")
      {:error, "oops"}
  """
  @spec err(reason :: any) :: err
  def err(reason), do: {:error, reason}

  @doc """
  Returns true if the argument is a `t:ok/0`.

      iex> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.is_ok?()
      true

      iex> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.is_ok?()
      false
  """
  @spec is_ok?(value :: t) :: boolean
  def is_ok?({:ok, _}), do: true
  def is_ok?({:error, _}), do: false

  @doc """
  Returns true if the result is `t:ok/0` and the value inside of it matches a predicate.

      iex> is_meaning_of_life = fn x -> x == 42 end
      ...> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.is_ok_and?(is_meaning_of_life)
      true

      iex> is_meaning_of_life = fn x -> x == 42 end
      ...> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.is_ok_and?(is_meaning_of_life)
      false
  """
  @spec is_ok_and?(value :: t, predicate :: (any -> boolean)) :: boolean
  def is_ok_and?({:error, _}, _func), do: false
  def is_ok_and?({:ok, val}, func), do: func.(val) == true

  @doc """
  Returns true if the argument is an `t:err/0`.

      iex> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.is_err?()
      false

      iex> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.is_err?()
      true
  """
  @spec is_err?(value :: t) :: boolean
  def is_err?({:ok, _}), do: false
  def is_err?({:error, _}), do: true

  @doc """
  Returns true if the result is `t:err/0` and the value inside of it matches a predicate.

      iex> is_not_found = fn err -> err == :not_found end
      ...> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.is_err_and?(is_not_found)
      false

      iex> is_not_found = fn err -> err == :not_found end
      ...> :not_found
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.is_err_and?(is_not_found)
      true
  """
  @spec is_err_and?(value :: t, predicate :: (any -> boolean)) :: boolean
  def is_err_and?({:ok, _}, _func), do: false
  def is_err_and?({:error, val}, func), do: func.(val) == true

  @doc """
  Is valid if and only if an `t:ok/0` is supplied.

      iex> check = fn
      ...>   val when OnePiece.Result.is_ok_result(val) -> true
      ...>   _ -> false
      ...> end
      ...> 42
      ...> |> OnePiece.Result.ok()
      ...> |> check.()
      true

      iex> check = fn
      ...>   val when OnePiece.Result.is_ok_result(val) -> true
      ...>   _ -> false
      ...> end
      ...> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> check.()
      false
  """
  @spec is_ok_result(value :: any) :: Macro.t()
  defguard is_ok_result(val) when is_tuple(val) and elem(val, 0) == :ok

  @doc """
  Is valid if and only if an `t:err/0` is supplied.

      iex> check = fn
      ...>   val when OnePiece.Result.is_err_result(val) -> true
      ...>   _ -> false
      ...> end
      ...> 42
      ...> |> OnePiece.Result.ok()
      ...> |> check.()
      false

      iex> check = fn
      ...>   val when OnePiece.Result.is_err_result(val) -> true
      ...>   _ -> false
      ...> end
      ...> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> check.()
      true
  """
  @spec is_err_result(value :: any) :: Macro.t()
  defguard is_err_result(val) when is_tuple(val) and elem(val, 0) == :error

  @doc """
  Returns true if the `t:ok/0` result contains the given value.

      iex> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.contains_ok?(42)
      true

      iex> 21
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.contains_ok?(42)
      false

      iex> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.contains_ok?(42)
      false
  """
  @spec contains_ok?(result :: t, value :: any) :: boolean
  def contains_ok?({:error, _}, _), do: false
  def contains_ok?({:ok, value}, value), do: true
  def contains_ok?({:ok, _}, _), do: false

  @doc """
  Returns true if the `t:err/0` result contains the given value.

      iex> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.contains_err?("oops")
      true

      iex> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.contains_err?("nop")
      false

      iex> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.contains_err?("ops")
      false
  """
  @spec contains_err?(result :: t, value :: any) :: boolean
  def contains_err?({:ok, _}, _), do: false
  def contains_err?({:error, value}, value), do: true
  def contains_err?({:error, _}, _), do: false

  @doc """
  When the value contained in an `t:ok/0` result then applies a function or returns the mapped value, wrapping the
  returning value in a `t:ok/0`, propagating the `t:err/0` result as it is.

  > #### Avoid Wrapping {: .info}
  > If you want to avoid the wrap then use `OnePiece.Result.when_ok/2` instead.

      iex> 21
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.map_ok(42)
      {:ok, 42}

      iex> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.map_ok(42)
      {:error, "oops"}

  You can also pass a function to achieve lazy evaluation:

      iex> meaning_of_life = fn x -> x * 2 end
      ...> 21
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.map_ok(meaning_of_life)
      {:ok, 42}
  """
  @spec map_ok(result :: t, on_ok :: (any -> any) | any) :: t
  def map_ok({:ok, val}, on_ok) when is_function(on_ok), do: ok(on_ok.(val))
  def map_ok({:ok, _val}, value), do: ok(value)
  def map_ok({:error, _} = error, _on_ok), do: error

  @doc ~S"""
  Applies a `on_ok` function to the contained value if `t:ok/0` otherwise applies a `on_err` function or return the
  `on_err` value if `t:err/0`.

      iex> meaning_of_life = fn x -> x * 2 end
      ...> 21
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.map_ok_or(meaning_of_life, 84)
      42

      iex> meaning_of_life = fn x -> x * 2 end
      ...> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.map_ok_or(meaning_of_life, 84)
      84

  > #### Lazy Evaluation {: .info}
  > It is recommended to pass a function as the default value, which is lazily evaluated.

      iex> meaning_of_life = fn x -> x * 2 end
      ...> went_wrong = fn reason -> "something went wrong because #{reason}" end
      ...> 21
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.map_ok_or(meaning_of_life, went_wrong)
      42

      iex> meaning_of_life = fn x -> x * 2 end
      ...> went_wrong = fn reason -> "something went wrong because #{reason}" end
      ...> "a sleepy bear"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.map_ok_or(meaning_of_life, went_wrong)
      "something went wrong because a sleepy bear"
  """
  @spec map_ok_or(result :: t, on_ok :: (any -> any), on_error :: any | (any -> any)) :: any
  def map_ok_or({:ok, val}, on_ok, _), do: on_ok.(val)
  def map_ok_or({:error, reason}, _, on_error) when is_function(on_error), do: on_error.(reason)
  def map_ok_or({:error, _}, _, on_error), do: on_error

  @doc """
  Applies a function or returns the value when a `t:ok/0` is given, or propagates the error.

      iex> 21
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.when_ok(42)
      42

      iex> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.when_ok(42)
      {:error, "oops"}

  You can also pass a function to achieve lazy evaluation:

      iex> meaning_of_life = fn x -> x * 2 end
      ...> 21
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.when_ok(meaning_of_life)
      42
  """
  @spec when_ok(result :: t, on_ok :: (any -> any) | any) :: err() | any
  def when_ok({:ok, val}, on_ok) when is_function(on_ok), do: on_ok.(val)
  def when_ok({:ok, _val}, value), do: value
  def when_ok({:error, _} = error, _), do: error

  @doc """
  Do an `and` with a `t:ok/0`.

  When passing two `t:ok/0` result, it returns the second `t:ok/0` value. When a `t:ok/0` and a `t:err/0` result, then
  returns the `t:err/0`. Otherwise, when passing two `t:err/0` result, it returns the earliest `t:err/0`.

      iex> 21
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.and_ok(OnePiece.Result.ok(42))
      {:ok, 42}

      iex> 21
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.and_ok(OnePiece.Result.err("something went wrong"))
      {:error, "something went wrong"}

      iex> "something went wrong"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.and_ok(OnePiece.Result.ok(42))
      {:error, "something went wrong"}

      iex> "something went wrong"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.and_ok(OnePiece.Result.err("late error"))
      {:error, "something went wrong"}
  """
  @spec and_ok(first_result :: t, second_result :: t) :: t
  def and_ok({:ok, _}, {:ok, _} = second_result), do: second_result
  def and_ok({:ok, _}, {:error, _} = second_result), do: second_result
  def and_ok({:error, _} = first_result, {:ok, _}), do: first_result
  def and_ok({:error, _} = first_result, {:error, _}), do: first_result

  @doc """
  Returns the contained `t:ok/0` value or a provided default.

      iex> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.unwrap_ok(21)
      42

      iex> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.unwrap_ok(21)
      21

  > #### Lazy Evaluation {: .info}
  > It is recommended to pass a function as the default value, which is lazily evaluated.

      iex> say_hello_world = fn _x -> "hello, world!" end
      ...> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.unwrap_ok(say_hello_world)
      42

      iex> say_hello_world = fn _x -> "hello, world!" end
      ...> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.unwrap_ok(say_hello_world)
      "hello, world!"
  """
  @spec unwrap_ok(result :: t, on_error :: any | (any -> any)) :: any
  def unwrap_ok({:ok, v}, _), do: v
  def unwrap_ok({:error, reason}, on_error) when is_function(on_error), do: on_error.(reason)
  def unwrap_ok({:error, _reason}, on_error), do: on_error

  @doc """
  Unwrap an `t:ok/0` result, or raise an exception.

      iex> try do
      ...>   42
      ...>   |> OnePiece.Result.ok()
      ...>   |> OnePiece.Result.unwrap_ok!()
      ...> rescue
      ...>   OnePiece.Result.OkUnwrapError -> "was a unwrap failure"
      ...> end
      42

      iex> try do
      ...>   "oops"
      ...>   |> OnePiece.Result.err()
      ...>   |> OnePiece.Result.unwrap_ok!()
      ...> rescue
      ...>   OnePiece.Result.OkUnwrapError -> "was a unwrap failure"
      ...> end
      "was a unwrap failure"
  """
  @spec unwrap_ok!(result :: t) :: any | no_return
  def unwrap_ok!({:ok, val}), do: val
  def unwrap_ok!({:error, reason}), do: raise(OkUnwrapError, reason: reason)

  @doc """
  Returns the contained `t:ok/0` value, or raise an exception with the given error message.

      iex> try do
      ...>   21
      ...>   |> OnePiece.Result.err()
      ...>   |> OnePiece.Result.expect_ok!("expected 42")
      ...> rescue
      ...>   e -> e.message
      ...> end
      "expected 42"

      iex> try do
      ...>   42
      ...>   |> OnePiece.Result.ok()
      ...>   |> OnePiece.Result.expect_ok!("expected 42")
      ...> rescue
      ...>   _ -> "was a unwrap failure"
      ...> end
      42
  """
  @spec expect_ok!(result :: t, message :: String.t()) :: any | no_return
  def expect_ok!({:ok, val}, _message), do: val
  def expect_ok!({:error, reason}, message), do: raise(ExpectedError, message: message, value: reason)

  @doc ~S"""
  Tap into `t:ok/0` results.

      iex> success_log = fn x -> "Success #{x}" end
      ...> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.tap_ok(success_log)
      {:ok, 42}
  """
  @spec tap_ok(result :: t, func :: (any -> any)) :: t
  def tap_ok(result, func), do: map_ok(result, &tap(&1, func))

  @doc ~S"""
  When the value contained in an `t:err/0` result then applies a function or returns the mapped value, wrapping the
  returning value in a `t:err/0`, propagating the `t:ok/0` result as it is.

  > #### Avoid Wrapping {: .info}
  > If you want to avoid the wrap then use `OnePiece.Result.when_err/2` instead.

        iex> 21
        ...> |> OnePiece.Result.err()
        ...> |> OnePiece.Result.map_err("must be 42")
        {:error, "must be 42"}

        iex> 42
        ...> |> OnePiece.Result.ok()
        ...> |> OnePiece.Result.map_err("must be 42")
        {:ok, 42}

  You can also pass a function to achieve lazy evaluation:

      iex> meaning_of_life = fn x -> "must be 42 instead of #{x}" end
      ...> 21
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.map_err(meaning_of_life)
      {:error, "must be 42 instead of 21"}
  """
  @spec map_err(result :: t, on_error :: (any -> any) | any) :: t
  def map_err({:ok, _} = result, _), do: result
  def map_err({:error, reason}, on_error) when is_function(on_error), do: err(on_error.(reason))
  def map_err({:error, _}, reason), do: err(reason)

  @doc """
  Applies a function or returns the value if the result is `t:err/0`, otherwise returns the `t:ok/0` value.

      iex> "something wrong happened"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.when_err("ooops")
      "ooops"

      iex> 2
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.when_err("ooops")
      {:ok, 2}

  You can also pass a function to achieve lazy evaluation:

      iex> failure = fn _error -> "lazy ooops" end
      ...> "something wrong happened"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.when_err(failure)
      "lazy ooops"
  """
  @spec when_err(result :: t, on_err :: (any -> t) | any) :: ok() | any
  def when_err({:ok, _} = resp, _), do: resp
  def when_err({:error, reason}, on_err) when is_function(on_err), do: on_err.(reason)
  def when_err({:error, _}, value), do: value

  @doc """
  Do an `and` with a `t:err/0`.

  When passing any `t:ok/0` result, it returns the first `t:ok/0` value. Otherwise, when passing two `t:err/0` results,
  then returns the second `t:err/0`.

      iex> 21
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.and_err(OnePiece.Result.ok(42))
      {:ok, 21}

      iex> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.and_err(OnePiece.Result.err("something went wrong"))
      {:ok, 42}

      iex> "something went wrong"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.and_err(OnePiece.Result.ok(42))
      {:ok, 42}

      iex> "something went wrong"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.and_err(OnePiece.Result.err("late error"))
      {:error, "late error"}
  """
  @spec and_err(first_result :: t, second_result :: t) :: t
  def and_err({:ok, _} = first_result, {:ok, _}), do: first_result
  def and_err({:ok, _} = first_result, {:error, _}), do: first_result
  def and_err({:error, _}, {:ok, _} = second_result), do: second_result
  def and_err({:error, _}, {:error, _} = second_result), do: second_result

  @doc """
  Unwrap an `t:err/0` result, or raise an exception.

      iex> try do
      ...>   "oops"
      ...>   |> OnePiece.Result.err()
      ...>   |> OnePiece.Result.unwrap_err!()
      ...> rescue
      ...>   OnePiece.Result.ErrUnwrapError -> "was a unwrap failure"
      ...> end
      "oops"

      iex> try do
      ...>   42
      ...>   |> OnePiece.Result.ok()
      ...>   |> OnePiece.Result.unwrap_err!()
      ...> rescue
      ...>   OnePiece.Result.ErrUnwrapError -> "was a unwrap failure"
      ...> end
      "was a unwrap failure"
  """
  @spec unwrap_err!(result :: t) :: any | no_return
  def unwrap_err!({:ok, val}), do: raise(ErrUnwrapError, value: val)
  def unwrap_err!({:error, reason}), do: reason

  @doc """
  Returns the contained `t:ok/0` value, or raise an exception with the given error message.

      iex> try do
      ...>   42
      ...>   |> OnePiece.Result.ok()
      ...>   |> OnePiece.Result.expect_err!("expected a oops")
      ...> rescue
      ...>   e -> e.message
      ...> end
      "expected a oops"

      iex> try do
      ...>   "oops"
      ...>   |> OnePiece.Result.err()
      ...>   |> OnePiece.Result.expect_err!("expected a oops")
      ...> rescue
      ...>   _ -> "was a unwrap failure"
      ...> end
      "oops"
  """
  @spec expect_err!(result :: t, message :: String.t()) :: any | no_return
  def expect_err!({:error, reason}, _message), do: reason
  def expect_err!({:ok, val}, message), do: raise(ExpectedError, message: message, value: val)

  @doc ~S"""
  Tap into `t:err/0` results.

      iex> failure_log = fn err -> "Failure because #{err}" end
      ...> "ooopsy"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.tap_err(failure_log)
      {:error, "ooopsy"}
  """
  @spec tap_err(result :: t, func :: (any -> any)) :: t
  def tap_err(result, func), do: map_err(result, &tap(&1, func))

  @doc ~S"""
  When `nil` is passed then calls the `on_nil` function and wrap the result into a `t:err/0`. When `t:t/0` is passed
  then returns it as it is. Otherwise, wraps the value into a `t:ok/0`.

      iex> OnePiece.Result.reject_nil(nil, "ooopps")
      {:error, "ooopps"}

      iex> OnePiece.Result.reject_nil(42, "ooopps")
      {:ok, 42}

      iex> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.reject_nil("ooopps")
      {:ok, 42}

      iex> "my error"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.reject_nil("ooopps")
      {:error, "my error"}

  > #### Lazy Evaluation {: .info}
  > It is recommended to pass a function as the default value, which is lazily evaluated.

      iex> new_error = fn -> "ooops" end
      ...> OnePiece.Result.reject_nil(nil, new_error)
      {:error, "ooops"}
  """
  @spec reject_nil(value :: any, on_nil :: any | (() -> any)) :: t
  def reject_nil(nil, on_nil) when is_function(on_nil), do: err(on_nil.())
  def reject_nil(nil, on_nil), do: err(on_nil)
  def reject_nil({:ok, _} = response, _), do: response
  def reject_nil({:error, _} = response, _), do: response
  def reject_nil(value, _), do: ok(value)

  @doc """
  Converts from a nested `t:t/0` to flatten `t:t/0`.

      iex> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.flatten()
      {:ok, 42}

      iex> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.flatten()
      {:error, {:ok, 42}}

      iex> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.flatten()
      {:error, "oops"}

      iex> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.flatten()
      {:error, {:error, "oops"}}
  """
  @spec flatten(result :: t) :: t
  def flatten(value), do: when_ok(value, &Function.identity/1)

  @doc """
  Iterate over `t:t/0` list unwrapping the `t:ok/0` values. It fails at the first `t:err/0`.

      iex> OnePiece.Result.collect([
      ...>   OnePiece.Result.ok(21),
      ...>   OnePiece.Result.ok(42),
      ...>   OnePiece.Result.ok(84),
      ...> ])
      {:ok, [21,42,84]}

      iex> OnePiece.Result.collect([
      ...>   OnePiece.Result.ok(21),
      ...>   OnePiece.Result.err("oops"),
      ...>   OnePiece.Result.ok(84),
      ...> ])
      {:error, "oops"}
  """
  @spec collect(Enum.t()) :: t
  def collect(result_list) do
    result_list
    |> Enum.map(&unwrap_ok!/1)
    |> ok()
  rescue
    err in OkUnwrapError ->
      err(err.reason)
  end

  @doc """
  Returns the contained `t:ok/0` value or `t:error/0` value from a `t:t/0`.

      iex> 42
      ...> |> OnePiece.Result.ok()
      ...> |> OnePiece.Result.unwrap()
      42

      iex> "oops"
      ...> |> OnePiece.Result.err()
      ...> |> OnePiece.Result.unwrap()
      "oops"
  """
  @spec unwrap(result :: t) :: any
  def unwrap({:ok, v}), do: v
  def unwrap({:error, v}), do: v
end

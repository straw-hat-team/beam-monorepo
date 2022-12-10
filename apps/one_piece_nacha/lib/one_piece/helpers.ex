defmodule OnePiece.Nacha.Helpers do
  import NimbleParsec

  def eol(combinator \\ empty()) do
    combinator
    |> ignore(choice([string("\r\n"), string("\n")]) |> label("EOL"))
    |> label("EOL")
  end

  def trace_number(combinator \\ empty()) do
    combinator
    |> integer(15)
    |> label("Trace Number")
  end

  def check_digit(combinator \\ empty()) do
    combinator
    |> integer(1)
    |> label("Check Digit")
  end

  def receiving_dfi_identification(combinator \\ empty()) do
    combinator
    |> ascii_string([], 8)
    |> label("Receiving DFI Identification")
  end

  def discretionary_data(combinator \\ empty()) do
    combinator
    |> ascii_string([], 2)
    |> label("Discretionary Data")
  end

  def individual_name(combinator \\ empty()) do
    combinator
    |> ascii_string([], 22)
    |> label("Individual Name / Receiving Company Name")
  end

  def individual_identification_number(combinator \\ empty()) do
    combinator
    |> ascii_string([], 15)
    |> label("Individual Identification Number")
  end

  def check_serial_number(combinator \\ empty()) do
    combinator
    |> ascii_string([], 15)
    |> label("Check Serial Number")
  end

  def transaction_code(combinator \\ empty()) do
    combinator
    |> integer(2)
    |> label("Transaction Code")
  end

  def record_type_code_entry_detail do
    string("6")
    |> label("Entry Detail Record Type Code")
  end

  def record_type_code_addenda do
    string("7")
    |> label("Addenda Record Type Code")
  end

  def dfi_account_number(combinator \\ empty()) do
    combinator
    |> ascii_string([], 17)
    |> label("DFI Account Number")
  end

  def amount(combinator \\ empty()) do
    combinator
    |> integer(10)
    |> label("Amount")
  end

  def addenda_record_indicator(combinator \\ empty()) do
    combinator
    |> integer(1)
    |> label("Addenda Record Indicator")
  end

  def trimmed_ascii_string(combinator \\ empty(), range, count_or_opts) do
    value =
      ascii_string(range, count_or_opts)
      |> map({String, :trim, []})

    concat(combinator, value)
  end
end

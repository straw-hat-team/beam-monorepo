defmodule OnePiece.Nacha.MteAddenda do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :addenda_type_code,
    :transaction_description,
    :network_identification_code,
    :terminal_identification_code,
    :transaction_serial_number,
    :transaction_date,
    :transaction_time,
    :terminal_location,
    :terminal_city,
    :terminal_state,
    :trace_number,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         record_type_code: Enum.at(parsed_line, 11),
         addenda_type_code: Enum.at(parsed_line, 10),
         transaction_description: Enum.at(parsed_line, 9),
         network_identification_code: Enum.at(parsed_line, 8),
         terminal_identification_code: Enum.at(parsed_line, 7),
         transaction_serial_number: Enum.at(parsed_line, 6),
         transaction_date: Enum.at(parsed_line, 5),
         transaction_time: Enum.at(parsed_line, 4),
         terminal_location: Enum.at(parsed_line, 3),
         terminal_city: Enum.at(parsed_line, 2),
         terminal_state: Enum.at(parsed_line, 1),
         trace_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def web_addenda do
    record_type_code_addenda()
    |> ascii_string([], 2)
    |> label("Addenda Type Code")
    |> ascii_string([], 7)
    |> label("Transaction Description")
    |> ascii_string([], 3)
    |> label("Network Identification Code")
    |> ascii_string([], 6)
    |> label("Terminal Identification Code")
    |> ascii_string([], 7)
    |> label("Transaction Serial Number")
    |> ascii_string([], 4)
    |> label("Transaction Date")
    |> ascii_string([], 6)
    |> label("Transaction Time")
    |> ascii_string([], 27)
    |> label("Terminal Location")
    |> ascii_string([], 15)
    |> label("Terminal City")
    |> ascii_string([], 2)
    |> label("Terminal State")
    |> ascii_string([], 15)
    |> label("Trace Number")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> label("MTE Addenda")
  end
end

defmodule OnePiece.Nacha.PosAddenda do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :addenda_type_code,
    :reference_information_one,
    :reference_information_two,
    :terminal_identification_code,
    :transaction_serial_number,
    :transaction_date,
    :authorization_code_or_card_expiration_date,
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
         reference_information_one: Enum.at(parsed_line, 9),
         reference_information_two: Enum.at(parsed_line, 8),
         terminal_identification_code: Enum.at(parsed_line, 7),
         transaction_serial_number: Enum.at(parsed_line, 6),
         transaction_date: Enum.at(parsed_line, 5),
         authorization_code_or_card_expiration_date: Enum.at(parsed_line, 4),
         terminal_location: Enum.at(parsed_line, 3),
         terminal_city: Enum.at(parsed_line, 2),
         terminal_state: Enum.at(parsed_line, 1),
         trace_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def pos_addenda do
    record_type_code_addenda()
    |> ascii_string([], 2)
    |> label("Addenda Type Code")
    |> ascii_string([], 7)
    |> label("Reference Information #1")
    |> ascii_string([], 3)
    |> label("Reference Information #2")
    |> ascii_string([], 6)
    |> label("Terminal Identification Code")
    |> ascii_string([], 6)
    |> label("Transaction Serial Number")
    |> ascii_string([], 4)
    |> label("Transaction Date")
    |> ascii_string([], 6)
    |> label("Authorization Code Or Card Expiration Date")
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
    |> label("POS Addenda")
  end
end

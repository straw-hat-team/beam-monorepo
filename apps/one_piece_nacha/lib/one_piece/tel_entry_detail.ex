defmodule OnePiece.Nacha.TelEntryDetail do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :transaction_code,
    :receiving_dfi_identification,
    :check_digit,
    :dfi_account_number,
    :amount,
    :individual_identification_number,
    :individual_name,
    :payment_type_code,
    :addenda_record_indicator,
    :trace_number,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         record_type_code: Enum.at(parsed_line, 10),
         transaction_code: Enum.at(parsed_line, 9),
         receiving_dfi_identification: Enum.at(parsed_line, 8),
         check_digit: Enum.at(parsed_line, 7),
         dfi_account_number: Enum.at(parsed_line, 6),
         amount: Enum.at(parsed_line, 5),
         individual_identification_number: Enum.at(parsed_line, 4),
         individual_name: Enum.at(parsed_line, 3),
         payment_type_code: Enum.at(parsed_line, 2),
         addenda_record_indicator: Enum.at(parsed_line, 1),
         trace_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def tel_entry_detail do
    record_type_code_entry_detail()
    |> transaction_code()
    |> receiving_dfi_identification()
    |> check_digit()
    |> dfi_account_number()
    |> amount()
    |> individual_identification_number()
    |> individual_name()
    |> ascii_string([], 2)
    |> label("Payment Type Code")
    |> addenda_record_indicator()
    |> trace_number()
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> label("TEL Entry Detail")
  end
end

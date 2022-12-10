defmodule OnePiece.Nacha.ShrEntryDetail do
  import NimbleParsec
  import OnePiece.Nacha.Helpers
  import OnePiece.Nacha.ShrAddenda, only: [shr_addenda: 0]

  @enforce_keys [
    :record_type_code,
    :transaction_code,
    :receiving_dfi_identification,
    :check_digit,
    :dfi_account_number,
    :amount,
    :card_expiration_date,
    :document_reference_number,
    :individual_card_account_number,
    :card_transaction_type_code,
    :addenda_record_indicator,
    :trace_number,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         record_type_code: Enum.at(parsed_line, 11),
         transaction_code: Enum.at(parsed_line, 10),
         receiving_dfi_identification: Enum.at(parsed_line, 9),
         check_digit: Enum.at(parsed_line, 8),
         dfi_account_number: Enum.at(parsed_line, 7),
         amount: Enum.at(parsed_line, 6),
         card_expiration_date: Enum.at(parsed_line, 5),
         document_reference_number: Enum.at(parsed_line, 4),
         individual_card_account_number: Enum.at(parsed_line, 3),
         card_transaction_type_code: Enum.at(parsed_line, 2),
         addenda_record_indicator: Enum.at(parsed_line, 1),
         trace_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def Shr_entry_detail do
    record_type_code_entry_detail()
    |> transaction_code()
    |> receiving_dfi_identification()
    |> check_digit()
    |> dfi_account_number()
    |> amount()
    |> ascii_string([], 4)
    |> label("Card Expiration Date")
    |> ascii_string([], 11)
    |> label("Document Reference Number")
    |> ascii_string([], 2)
    |> label("Card Transaction Type Code")
    |> addenda_record_indicator()
    |> trace_number()
    |> eol()
    |> optional(shr_addenda())
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> label("SHR Entry Detail")
  end
end

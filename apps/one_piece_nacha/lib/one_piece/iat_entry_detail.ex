defmodule OnePiece.Nacha.IatEntryDetail do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :transaction_code,
    :go_identification_receiving_dfi_identification,
    :check_digit,
    :number_of_addenda_records,
    :reserved,
    :amount,
    :foreign_receivers_account_number_dfi_account_number,
    :reserved,
    :gateway_operator_ofac_screening_indicator,
    :secondary_ofac_screening_indicator,
    :addenda_record_indicator,
    :trace_number,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         record_type_code: Enum.at(parsed_line, 12),
         transaction_code: Enum.at(parsed_line, 11),
         go_identification_receiving_dfi_identification: Enum.at(parsed_line, 10),
         check_digit: Enum.at(parsed_line, 9),
         number_of_addenda_records: Enum.at(parsed_line, 8),
         reserved: Enum.at(parsed_line, 7),
         amount: Enum.at(parsed_line, 6),
         foreign_receivers_account_number_dfi_account_number: Enum.at(parsed_line, 5),
         reserved: Enum.at(parsed_line, 4),
         gateway_operator_ofac_screening_indicator: Enum.at(parsed_line, 3),
         secondary_ofac_screening_indicator: Enum.at(parsed_line, 2),
         addenda_record_indicator: Enum.at(parsed_line, 1),
         trace_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def iat_entry_detail do
    record_type_code_entry_detail()
    |> ascii_string([], 2)
    |> label("Transaction Code")
    |> ascii_string([], 8)
    |> label("Go Identification/ Receiving DFI Identification")
    |> ascii_string([], 1)
    |> label("Check Digit")
    |> ascii_string([], 4)
    |> label("Number Of Addenda Records")
    |> ascii_string([], 13)
    |> label("Reserved")
    |> ascii_string([], 10)
    |> label("Amount")
    |> ascii_string([], 35)
    |> label("Foreign Receivers Account Number / DFI Account Number")
    |> ascii_string([], 2)
    |> label("Reserved")
    |> ascii_string([], 1)
    |> label("Gateway Operator Ofac Screening Indicator")
    |> ascii_string([], 1)
    |> label("Secondary OFAC Screening Indicator")
    |> ascii_string([], 1)
    |> label("Addenda Record Indicator")
    |> ascii_string([], 15)
    |> label("Trace Number")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> label("IAT Entry Detail")
  end
end

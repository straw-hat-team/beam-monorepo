defmodule OnePiece.Nacha.EnrEntryDetail do
  import NimbleParsec
  import OnePiece.Nacha.Helpers
  import OnePiece.Nacha.EnrAddenda, only: [enr_addenda: 0]

  @enforce_keys [
    :record_type_code,
    :transaction_code,
    :receiving_dfi_identification,
    :check_digit,
    :dfi_account_number,
    :amount,
    :identification_number,
    :number_of_addenda_records,
    :receiving_company_name,
    :reserved,
    :discretionary_data,
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
         receiving_dfi_identification: Enum.at(parsed_line, 10),
         check_digit: Enum.at(parsed_line, 9),
         dfi_account_number: Enum.at(parsed_line, 8),
         amount: Enum.at(parsed_line, 7),
         identification_number: Enum.at(parsed_line, 6),
         number_of_addenda_records: Enum.at(parsed_line, 5),
         receiving_company_name: Enum.at(parsed_line, 4),
         reserved: Enum.at(parsed_line, 3),
         discretionary_data: Enum.at(parsed_line, 2),
         addenda_record_indicator: Enum.at(parsed_line, 1),
         trace_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def enr_entry_detail do
    record_type_code_entry_detail()
    |> transaction_code()
    |> receiving_dfi_identification()
    |> check_digit()
    |> dfi_account_number()
    |> amount()
    |> ascii_string([], 15)
    |> label("Identification Number")
    |> ascii_string([], 4)
    |> label("Number of Addenda Records")
    |> ascii_string([], 16)
    |> label("Receiving Company Name / ID Number")
    |> ascii_string([], 2)
    |> label("Reserved")
    |> discretionary_data()
    |> addenda_record_indicator()
    |> trace_number()
    |> eol()
    |> optional(enr_addenda())
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> label("ENR Entry Detail")
  end
end

defmodule OnePiece.Nacha.FirstIatAddenda do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :addenda_type_code,
    :transaction_type_code,
    :foreign_payment_amount,
    :foreign_trace_number,
    :receiving_company_name,
    :reserved,
    :entry_detail_sequence_number,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         record_type_code: Enum.at(parsed_line, 7),
         addenda_type_code: Enum.at(parsed_line, 6),
         transaction_type_code: Enum.at(parsed_line, 5),
         foreign_payment_amount: Enum.at(parsed_line, 4),
         foreign_trace_number: Enum.at(parsed_line, 3),
         receiving_company_name: Enum.at(parsed_line, 2),
         reserved: Enum.at(parsed_line, 1),
         entry_detail_sequence_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def first_iat_addenda do
    record_type_code_addenda()
    |> ascii_string([], 2)
    |> label("Addenda Type Code")
    |> ascii_string([], 3)
    |> label("Transaction Type Code")
    |> ascii_string([], 18)
    |> label("Foreign Payment Amount")
    |> ascii_string([], 22)
    |> label("Foreign Trace Number")
    |> ascii_string([], 35)
    |> label("Receiving Company Name/Individual Name")
    |> ascii_string([], 6)
    |> label("Reserved")
    |> ascii_string([], 7)
    |> label("Entry Detail Sequence Number")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> label("First IAT Addenda")
  end
end

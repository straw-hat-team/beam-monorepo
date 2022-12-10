defmodule OnePiece.Nacha.RemittanceInformationIatAddenda do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :addenda_type_code,
    :payment_related_information,
    :addenda_sequence_number,
    :entry_detail_sequence_number,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
          record_type_code: Enum.at(parsed_line, 4),
          addenda_type_code: Enum.at(parsed_line, 3),
          payment_related_information: Enum.at(parsed_line, 2),
          addenda_sequence_number: Enum.at(parsed_line, 1),
          entry_detail_sequence_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def remittance_information_iat_addenda do
    record_type_code_addenda()
    |> ascii_string([], 2)
    |> label("Addenda Type Code")
    |> ascii_string([], 80)
    |> label("Payment Related Information")
    |> ascii_string([], 4)
    |> label("Addenda Sequence Number")
    |> ascii_string([], 7)
    |> label("Entry Detail Sequence Number")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> label("Remittance Information IAT Addenda")
  end
end

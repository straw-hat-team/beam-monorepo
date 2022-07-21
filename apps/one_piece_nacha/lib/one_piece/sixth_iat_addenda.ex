defmodule OnePiece.Nacha.SixthIatAddenda do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :addenda_type_code,
    :receiver_identification_number,
    :receiver_street_address,
    :reserved,
    :entry_detail_sequence_number,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
          record_type_code: Enum.at(parsed_line, 5),
          addenda_type_code: Enum.at(parsed_line, 4),
          receiver_identification_number: Enum.at(parsed_line, 3),
          receiver_street_address: Enum.at(parsed_line, 2),
          reserved: Enum.at(parsed_line, 1),
          entry_detail_sequence_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def sixth_iat_addenda do
    record_type_code_addenda()
    |> ascii_string([], 2)
    |> label("Addenda Type Code")
    |> ascii_string([], 15)
    |> label("Receiver Identification Number")
    |> ascii_string([], 35)
    |> label("Receiver Street Address")
    |> ascii_string([], 34)
    |> label("Reserved")
    |> ascii_string([], 7)
    |> label("Entry Detail Sequence Number")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> label("Sixth IAT Addenda")
  end
end

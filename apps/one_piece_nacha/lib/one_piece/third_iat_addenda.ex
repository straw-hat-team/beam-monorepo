defmodule OnePiece.Nacha.ThirdIatAddenda do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :addenda_type_code,
    :originator_city_and_state,
    :originator_country_and_postal_code,
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
         originator_city_and_state: Enum.at(parsed_line, 3),
         originator_country_and_postal_code: Enum.at(parsed_line, 2),
         reserved: Enum.at(parsed_line, 1),
         entry_detail_sequence_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def third_iat_addenda do
    record_type_code_addenda()
    |> ascii_string([], 2)
    |> label("Addenda Type Code")
    |> ascii_string([], 2)
    |> label("Originator City & State/Province")
    |> ascii_string([], 2)
    |> label("Originator Country & Postal Code")
    |> ascii_string([], 2)
    |> label("Reserved")
    |> ascii_string([], 2)
    |> label("Entry Detail Sequence Number")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> label("Third IAT Addenda")
  end
end

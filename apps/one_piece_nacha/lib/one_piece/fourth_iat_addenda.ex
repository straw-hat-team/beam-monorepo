defmodule OnePiece.Nacha.FourthIatAddenda do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :addenda_type_code,
    :originating_dfi_name,
    :originating_dfi_identification_number_qualifier,
    :originating_dfi_identification,
    :originating_dfi_branch_country_code,
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
         originating_dfi_name: Enum.at(parsed_line, 5),
         originating_dfi_identification_number_qualifier: Enum.at(parsed_line, 4),
         originating_dfi_identification: Enum.at(parsed_line, 3),
         originating_dfi_branch_country_code: Enum.at(parsed_line, 2),
         reserved: Enum.at(parsed_line, 1),
         entry_detail_sequence_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def fourth_iat_addenda do
    record_type_code_addenda()
    |> ascii_string([], 2)
    |> label("Addenda Type Code")
    |> ascii_string([], 35)
    |> label("Originating Dfi Name")
    |> ascii_string([], 2)
    |> label("Originating Dfi Identification Number Qualifier")
    |> ascii_string([], 34)
    |> label("Originating Dfi Identification")
    |> ascii_string([], 3)
    |> label("Originating Dfi Branch Country Code")
    |> ascii_string([], 10)
    |> label("Reserved")
    |> ascii_string([], 7)
    |> label("Entry Detail Sequence Number")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> label("Fourth IAT Addenda")
  end
end

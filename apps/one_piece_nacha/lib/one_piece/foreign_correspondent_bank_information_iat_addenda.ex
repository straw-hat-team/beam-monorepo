defmodule OnePiece.Nacha.ForeignCorrespondentBankInformationIatAddenda do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :addenda_type_code,
    :foreign_correspondent_bank_name,
    :foreign_correspondent_bank_identification_number_qualifier,
    :foreign_correspondent_bank_identification_number,
    :foreign_correspondent_bank_branch_country_code,
    :reserved,
    :addenda_sequence_number,
    :entry_detail_sequence_number,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         record_type_code: Enum.at(parsed_line, 8),
         addenda_type_code: Enum.at(parsed_line, 7),
         foreign_correspondent_bank_name: Enum.at(parsed_line, 6),
         foreign_correspondent_bank_identification_number_qualifier: Enum.at(parsed_line, 5),
         foreign_correspondent_bank_identification_number: Enum.at(parsed_line, 4),
         foreign_correspondent_bank_branch_country_code: Enum.at(parsed_line, 3),
         reserved: Enum.at(parsed_line, 2),
         addenda_sequence_number: Enum.at(parsed_line, 1),
         entry_detail_sequence_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def foreign_correspondent_bank_information_iat_addenda do
    record_type_code_addenda()
    |> ascii_string([], 2)
    |> label("Addenda Type Code")
    |> ascii_string([], 35)
    |> label("Foreign Correspondent Bank Name")
    |> ascii_string([], 2)
    |> label("Foreign Correspondent Bank Identification Number Qualifier")
    |> ascii_string([], 34)
    |> label("Foreign Correspondent Bank Identification Number")
    |> ascii_string([], 3)
    |> label("Foreign Correspondent Bank Branch Country Code")
    |> ascii_string([], 6)
    |> label("Reserved")
    |> ascii_string([], 4)
    |> label("Addenda Sequence Number")
    |> ascii_string([], 7)
    |> label("Entry Detail Sequence Number")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> label("Foreign Correspondent Bank Information IAT Addenda")
  end
end

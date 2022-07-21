defmodule OnePiece.Nacha.IatBatchHeader do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :service_class_code,
    :iat_indicator,
    :foreign_exchange_indicator,
    :foreign_exchange_reference_indicator,
    :foreign_exchange_reference,
    :iso_destination_country_code,
    :originator_identification,
    :standard_entry_class_code,
    :company_entry_description,
    :iso_originating_currency_code,
    :iso_destination_currency_code,
    :effective_entry_date,
    :settlement_date,
    :originator_status_code,
    :originating_dfi_identification,
    :batch_number,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         record_type_code: Enum.at(parsed_line, 16),
         service_class_code: Enum.at(parsed_line, 15),
         iat_indicator: Enum.at(parsed_line, 14),
         foreign_exchange_indicator: Enum.at(parsed_line, 13),
         foreign_exchange_reference_indicator: Enum.at(parsed_line, 12),
         foreign_exchange_reference: Enum.at(parsed_line, 11),
         iso_destination_country_code: Enum.at(parsed_line, 10),
         originator_identification: Enum.at(parsed_line, 9),
         standard_entry_class_code: Enum.at(parsed_line, 8),
         company_entry_description: Enum.at(parsed_line, 7),
         iso_originating_currency_code: Enum.at(parsed_line, 6),
         iso_destination_currency_code: Enum.at(parsed_line, 5),
         effective_entry_date: Enum.at(parsed_line, 4),
         settlement_date: Enum.at(parsed_line, 3),
         originator_status_code: Enum.at(parsed_line, 2),
         originating_dfi_identification: Enum.at(parsed_line, 1),
         batch_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def iat_batch_header do
    string("5")
    |> label("Record Type Code")
    |> ascii_string([], 3)
    |> label("Service Class Code")
    |> ascii_string([], 16)
    |> label("IAT Indicator")
    |> ascii_string([], 2)
    |> label("Foreign Exchange Indicator")
    |> ascii_string([], 1)
    |> label("Foreign Exchange Reference Indicator")
    |> ascii_string([], 15)
    |> label("Foreign Exchange Reference")
    |> ascii_string([], 2)
    |> label("ISO Destination Country Code")
    |> ascii_string([], 10)
    |> label("Originator Identification")
    |> ascii_string([], 3)
    |> label("Standard Entry Class Code")
    |> ascii_string([], 10)
    |> label("Company Entry Description")
    |> ascii_string([], 3)
    |> label("ISO Originating Currency Code")
    |> ascii_string([], 3)
    |> label("ISO Destination Currency Code")
    |> ascii_string([], 6)
    |> label("Effective Entry Date")
    |> ascii_string([], 3)
    |> label("Settlement Date")
    |> ascii_string([], 1)
    |> label("Originator Status Code")
    |> ascii_string([], 8)
    |> label("Go Identification / Originating DFI Identification")
    |> ascii_string([], 7)
    |> label("Batch Number")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> unwrap_and_tag(:batch_header)
    |> label("IAT Batch Header")
  end
end

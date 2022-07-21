defmodule OnePiece.Nacha.BatchHeader do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :service_class_code,
    :company_name,
    :company_discretionary_data,
    :company_identification,
    :standard_entry_class_code,
    :company_entry_description,
    :company_descriptive_date,
    :effective_entry_date,
    :settlement_date,
    :originator_status_code,
    :odfi_identification,
    :batch_number,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         record_type_code: Enum.at(parsed_line, 12),
         service_class_code: Enum.at(parsed_line, 11),
         company_name: Enum.at(parsed_line, 10),
         company_discretionary_data: Enum.at(parsed_line, 9),
         company_identification: Enum.at(parsed_line, 8),
         standard_entry_class_code: Enum.at(parsed_line, 7),
         company_entry_description: Enum.at(parsed_line, 6),
         company_descriptive_date: Enum.at(parsed_line, 5),
         effective_entry_date: Enum.at(parsed_line, 4),
         settlement_date: Enum.at(parsed_line, 3),
         originator_status_code: Enum.at(parsed_line, 2),
         odfi_identification: Enum.at(parsed_line, 1),
         batch_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def batch_header do
    string("5")
    |> label("Record Type Code")
    |> integer(3)
    |> label("Service Class Code")
    |> trimmed_ascii_string([], 16)
    |> label("Company Name")
    |> ascii_string([], 20)
    |> label("Company Discretionary Data")
    |> trimmed_ascii_string([], 10)
    |> label("Company Identification")
    |> ascii_string([], 3)
    |> label("Standard Entry Class Code")
    |> trimmed_ascii_string([], 10)
    |> label("Company Entry Description")
    # TODO: is this a date or string?
    |> ascii_string([], 6)
    |> label("Company Descriptive Date")
    # TODO: date
    |> ascii_string([], 6)
    |> label("Effective Entry Date")
    # TODO: date
    |> ascii_string([], 3)
    |> label("Settlement Date")
    |> ascii_string([], 1)
    |> label("Originator Status Code")
    |> ascii_string([], 8)
    |> label("Originating DFI Identification")
    |> integer(7)
    |> label("Batch Number")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> unwrap_and_tag(:batch_header)
    |> label("Batch Header")
  end
end

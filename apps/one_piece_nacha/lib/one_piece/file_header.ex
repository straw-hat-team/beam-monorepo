defmodule OnePiece.Nacha.FileHeader do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :priority_code,
    :immediate_destination,
    :immediate_origin,
    :file_creation_date,
    :file_creation_time,
    :file_id_modifier,
    :record_size,
    :blocking_factor,
    :format_code,
    :immediate_destination_name,
    :immediate_origin_name,
    :reference_code,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         record_type_code: Enum.at(parsed_line, 12),
         priority_code: Enum.at(parsed_line, 11),
         immediate_destination: Enum.at(parsed_line, 10),
         immediate_origin: Enum.at(parsed_line, 9),
         file_creation_date: Enum.at(parsed_line, 8),
         file_creation_time: Enum.at(parsed_line, 7),
         file_id_modifier: Enum.at(parsed_line, 6),
         record_size: Enum.at(parsed_line, 5),
         blocking_factor: Enum.at(parsed_line, 4),
         format_code: Enum.at(parsed_line, 3),
         immediate_destination_name: Enum.at(parsed_line, 2),
         immediate_origin_name: Enum.at(parsed_line, 1),
         reference_code: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def file_header do
    string("1")
    |> label("Record Type Code")
    |> integer(2)
    |> label("Priority Code")
    |> trimmed_ascii_string([], 10)
    |> label("Immediate Destination") # bTTTTAAAAC
    |> trimmed_ascii_string([], 10)
    |> label("Immediate Origin")
    # TODO: Date
    |> ascii_string([], 6)
    |> label("File Creation Date")
    # TODO: Time
    |> ascii_string([], 4)
    |> label("File Creation Time")
    |> ascii_string([], 1)
    |> label("File ID Modifier")
    |> string("094")
    |> label("Record Size")
    |> string("10")
    |> label("Blocking Factor")
    |> string("1")
    |> label("Format code")
    |> trimmed_ascii_string([], 23)
    |> label("Immediate Destination Name")
    |> trimmed_ascii_string([], 23)
    |> label("Immediate Origin Name")
    |> ascii_string([], 8)
    |> label("Reference Code")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> unwrap_and_tag(:file_header)
    |> label("File Header")
  end
end

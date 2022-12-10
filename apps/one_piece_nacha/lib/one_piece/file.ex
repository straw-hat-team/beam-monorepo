defmodule OnePiece.Nacha.File do
  # https://achdevguide.nacha.org/ach-file-details
  # https://secureinstantpayments.com/sip/help/interface_specs/external/NACHA_format.pdf
  # https://www.independent-bank.com/_/kcms-doc/174/59908/20201006_NACHA_FileLayoutGuide_Final.pdf
  # https://www.chase.com/content/dam/chaseonline/en/demos/cbo/pdfs/cbo_nacha_filespecs.pdf
  # https://files.nc.gov/ncosc/documents/eCommerce/bank_of_america_nacha_file_specs.pdf
  # https://www.nachaoperatingrulesonline.org/2.16334/s017
  # https://github.com/freight-trust/NACHA


  import NimbleParsec
  import OnePiece.Nacha.FileHeader, only: [file_header: 0]
  import OnePiece.Nacha.FileControl, only: [file_control: 0]
  import OnePiece.Nacha.Batch, only: [batches: 0]

  @enforce_keys [
    :file_header,
    :batches,
    :file_control,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         file_header: parsed_line[:file_header],
         batches: parsed_line[:batches],
         file_control: parsed_line[:file_control],
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  file =
    file_header()
    |> concat(batches())
    |> concat(file_control())
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> unwrap_and_tag(:file)
    |> label("File")

  defparsec(:decode_file, file)
end

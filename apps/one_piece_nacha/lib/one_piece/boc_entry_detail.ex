defmodule OnePiece.Nacha.BocEntryDetail do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :transaction_code,
    :receiving_dfi_identification,
    :check_digit,
    :dfi_account_number,
    :amount,
    :check_serial_number,
    :individual_name,
    :discretionary_data,
    :addenda_record_indicator,
    :trace_number,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
          record_type_code: Enum.at(parsed_line, 10),
          transaction_code: Enum.at(parsed_line, 9),
          receiving_dfi_identification: Enum.at(parsed_line, 8),
          check_digit: Enum.at(parsed_line, 7),
          dfi_account_number: Enum.at(parsed_line, 6),
          amount: Enum.at(parsed_line, 5),
          check_serial_number: Enum.at(parsed_line, 4),
          individual_name: Enum.at(parsed_line, 3),
          discretionary_data: Enum.at(parsed_line, 2),
          addenda_record_indicator: Enum.at(parsed_line, 1),
          trace_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def boc_entry_detail do
    record_type_code_entry_detail()
    |> transaction_code()
    |> receiving_dfi_identification()
    |> check_digit()
    |> dfi_account_number()
    |> amount()
    |> check_serial_number()
    |> individual_name()
    |> discretionary_data()
    |> addenda_record_indicator()
    |> trace_number()
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> label("BOC Entry Detail")
  end
end

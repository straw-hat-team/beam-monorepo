defmodule OnePiece.Wire.Decoder do
  import NimbleParsec

  eol = choice([string("\r\n"), string("\n")]) |> label("EOL")

  interface_data =
    ascii_string([], 8)
    |> label("Interface Data")

  message_disposition_tag =
    string("{1100}")
    |> label("Message Disposition Tag")
    |> ascii_string([], 2)
    |> label("Format Version")
    |> ascii_string([], 1)
    |> label("Test Production Code")
    |> ascii_string([], 1)
    |> label("Message Duplication Code")
    |> ascii_string([], 1)
    |> label("Message Status Indicator")

  receipt_timestamp_tag =
    string("{1110}")
    |> label("Receipt Timestamp Tag")
    |> ascii_string([], 4)
    |> label("Receipt Date")
    |> ascii_string([], 4)
    |> label("Receipt Time")
    |> ascii_string([], 4)
    |> label("Receipt Application ID")

  omad_tag =
    string("{1120}")
    |> label("OMAD Tag")
    |> ascii_string([], 8)
    |> label("Output Cycle Date")
    |> ascii_string([], 8)
    |> label("Output Destination ID")
    |> ascii_string([], 6)
    |> label("Output Sequence Number")
    |> ascii_string([], 4)
    |> label("Output Date")
    |> ascii_string([], 4)
    |> label("Output Time")
    |> ascii_string([], 4)
    |> label("Output FRB Application ID")

  delimiter = string("*") |> label("Delimiter")

  error_tag =
    string("{1130}")
    |> label("Error Tag")
    |> ascii_string([], 1)
    |> label("Error Category")
    |> ascii_string([], 3)
    |> label("Error Code")
    |> ascii_string([], min: 0, max: 35)
    |> label("Error Description")
    |> concat(delimiter)

  sender_supplied_information_tag =
    string("{1500}")
    |> label("Sender Supplied Information Tag")
    |> ascii_string([], 2)
    |> label("Format Version")
    |> ascii_string([], 8)
    |> label("URC")
    |> ascii_string([], 1)
    |> label("Test Production Code")
    |> ascii_string([], 1)
    |> label("Message Duplication Code")

  type_subtype_tag =
    string("{1510}")
    |> label("Type Subtype Tag")
    |> ascii_string([], 2)
    |> label("Type Code")
    |> ascii_string([], 2)
    |> label("Subtype Code")

  imad_tag =
    string("{1520}")
    |> label("Type Subtype Tag")
    |> ascii_string([], 8)
    |> label("Input Cycle Date")
    |> ascii_string([], 8)
    |> label("Input Source")
    |> ascii_string([], 6)
    |> label("Input Sequence Number")

  amount_tag =
    string("{2000}")
    |> label("Amount Tag")
    |> ascii_string([], 12)
    |> label("Amount")

  sender_di_tag =
    string("{3100}")
    |> label("Sender DI Tag")
    |> ascii_string([], 9)
    |> label("Sender ABA Number")
    |> ascii_string([], min: 0, max: 18)
    |> label("Sender Short Name")
    |> concat(delimiter)

  sender_reference_tag =
    string("{3100}")
    |> label("Sender Reference Tag")
    |> ascii_string([], min: 1, max: 16)
    |> label("Sender Reference")
    |> concat(delimiter)

  receiver_di_tag =
    string("{3400}")
    |> label("Receiver DI Tag")
    |> ascii_string([], 9)
    |> label("Receiver ABA Number")
    |> ascii_string([], min: 0, max: 18)
    |> label("Receiver Short Name")
    |> concat(delimiter)

  previous_message_identifier_tag =
    string("{3500}")
    |> label("Previous Message Identifier Tag")
    |> ascii_string([], 22)
    |> label("Previous Message Identifier")

  business_function_tag =
    string("{3600}")
    |> label("Business Function Tag")
    |> ascii_string([], 3)
    |> label("Business Function Code")
    |> ascii_string([], min: 0, max: 3)
    |> label("Transaction Type Code")
    |> concat(delimiter)

  local_instrument_tag =
    string("{3610}")
    |> label("Local Instrument Tag")
    |> ascii_string([], 4)
    |> label("Local Instrument")
    |> ascii_string([], min: 0, max: 35)
    |> label("Proprietary Code")
    |> concat(delimiter)

  payment_notification_tag =
    string("{3620}")
    |> label("Payment Notification Tag")
    |> ascii_string([], 1)
    |> label("Payment Notification Indicator")
    |> ascii_string([], min: 0, max: 2080)
    |> label("Contact Notification Electronic Address")
    |> concat(delimiter)
    |> ascii_string([], min: 0, max: 140)
    |> label("Contact Name")
    |> concat(delimiter)
    |> ascii_string([], min: 0, max: 35)
    |> label("Contact Phone Number")
    |> concat(delimiter)
    |> ascii_string([], min: 0, max: 35)
    |> label("Contact Mobile Number")
    |> concat(delimiter)
    |> ascii_string([], min: 0, max: 35)
    |> label("Contact Fax Number")
    |> concat(delimiter)
    |> ascii_string([], min: 0, max: 35)
    |> label("End-To-End ID")
    |> concat(delimiter)

  changes_tag =
    string("{3700}")
    |> label("Changes Tag")
    |> ascii_string([], 1)
    |> label("Details of Changes")
    |> ascii_string([], min: 0, max: 15)
    |> label("Sender Changes 1")
    |> concat(delimiter)
    |> ascii_string([], min: 0, max: 15)
    |> label("Sender Changes 2")
    |> concat(delimiter)
    |> ascii_string([], min: 0, max: 15)
    |> label("Sender Changes 3")
    |> concat(delimiter)
    |> ascii_string([], min: 0, max: 15)
    |> label("Sender Changes 4")
    |> concat(delimiter)

  #  defparsec(:decode_file, file)
end

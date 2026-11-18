defmodule Trogon.Nacha.Batch do
  import NimbleParsec
  import Trogon.Nacha.BatchHeader, only: [batch_header: 0]
  import Trogon.Nacha.BatchControl, only: [batch_control: 0]
  import Trogon.Nacha.CtxEntryDetail, only: [ctx_entry_detail: 0]
  import Trogon.Nacha.CcdEntryDetail, only: [ccd_entry_detail: 0]
  import Trogon.Nacha.WebEntryDetail, only: [web_entry_detail: 0]
  import Trogon.Nacha.TelEntryDetail, only: [tel_entry_detail: 0]
  import Trogon.Nacha.PpdEntryDetail, only: [ppd_entry_detail: 0]
  import Trogon.Nacha.TrcEntryDetail, only: [trc_entry_detail: 0]
  import Trogon.Nacha.XckEntryDetail, only: [xck_entry_detail: 0]
  import Trogon.Nacha.RckEntryDetail, only: [rck_entry_detail: 0]
  import Trogon.Nacha.ArcEntryDetail, only: [arc_entry_detail: 0]
  import Trogon.Nacha.BocEntryDetail, only: [boc_entry_detail: 0]
  import Trogon.Nacha.PopEntryDetail, only: [pop_entry_detail: 0]
  import Trogon.Nacha.PosEntryDetail, only: [pos_entry_detail: 0]
  import Trogon.Nacha.CieEntryDetail, only: [cie_entry_detail: 0]
  import Trogon.Nacha.TrxEntryDetail, only: [trx_entry_detail: 0]
  import Trogon.Nacha.ShrEntryDetail, only: [shr_entry_detail: 0]
  import Trogon.Nacha.DneEntryDetail, only: [dne_entry_detail: 0]
  import Trogon.Nacha.EnrEntryDetail, only: [enr_entry_detail: 0]
  import Trogon.Nacha.MteEntryDetail, only: [mte_entry_detail: 0]

  @enforce_keys [
    :batch_header,
    :entry_details,
    :batch_control,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         batch_header: parsed_line[:batch_header],
         entry_details: parsed_line[:entry_details],
         batch_control: parsed_line[:batch_control],
         __parsing_info__: Trogon.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def batches do
    batch_record =
      choice([
        ppd_entry_detail(),
        tel_entry_detail(),
        web_entry_detail(),
        ccd_entry_detail(),
        ctx_entry_detail(),
        trc_entry_detail(),
        xck_entry_detail(),
        rck_entry_detail(),
        arc_entry_detail(),
        boc_entry_detail(),
        pop_entry_detail(),
        pos_entry_detail(),
        cie_entry_detail(),
        trx_entry_detail(),
        shr_entry_detail(),
        dne_entry_detail(),
        enr_entry_detail(),
        mte_entry_detail()
      ])
      |> label("Batch Record")

    entry_details =
      batch_record
      |> repeat()
      |> tag(:entry_details)
      |> label("Entry Details")

    batch =
      batch_header()
      |> concat(entry_details)
      |> concat(batch_control())
      |> label("Batch")

    batch
    |> repeat()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> tag(:batches)
    |> label("Batches")
  end
end

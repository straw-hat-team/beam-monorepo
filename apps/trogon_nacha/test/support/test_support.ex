defmodule TestSupport do
  import ExUnit.Assertions

  @fixtures_dir Path.join([__DIR__, "..", "fixtures"])

  def list_all_files(name) do
    dir_path = Path.join(@fixtures_dir, name)

    dir_path
    |> File.ls!()
    |> Enum.reject(&File.dir?(Path.join(dir_path, &1)))
  end

  def read_fixture(name) do
    File.read!(Path.join(@fixtures_dir, name))
  end

  def moov_ach_create_file_from_nacha(file_id, nacha) do
    Req.new()
    |> Req.Request.put_header("content-type", "text/plain")
    |> Req.post!(url: "http://localhost:7080/files/#{file_id}", body: nacha)
    |> Map.get(:body)
  end

  def assert_match_moov_ach_file(moov_file, nacha_file, opts \\ []) do
    %{moov_file: moov_file, nacha_file: nacha_file, opts: opts} |> dbg()

    moov_file = normalize_adv_file(moov_file)

    for key <- Map.keys(moov_file) do
      match_moov_ach_file(key, moov_file, nacha_file, opts)
    end
  end

  defp match_moov_ach_file("fileHeader" = key, moov_file, nacha_file, opts) do
    for file_header_key <- Map.keys(moov_file[key]) do
      match_moov_ach_file(key, file_header_key, moov_file[key][file_header_key], nacha_file, opts)
    end
  end

  defp match_moov_ach_file("fileControl" = key, moov_file, nacha_file, opts) do
    for file_control_key <- Map.keys(moov_file[key]) do
      match_moov_ach_file(key, file_control_key, moov_file[key][file_control_key], nacha_file, opts)
    end
  end

  defp match_moov_ach_file("batches" = key, moov_file, nacha_file, opts) do
    Enum.with_index(moov_file[key], fn batch, index ->
      batch = normalize_adv_batch(batch)

      for batch_key <- Map.keys(batch) do
        match_moov_ach_file(key, batch_key, batch[batch_key], Enum.at(nacha_file.batches, index), opts)
      end
    end)
  end

  defp match_moov_ach_file("id", _moov_file, _nacha_file, _opts) do
    :skip
  end

  defp match_moov_ach_file("validateOpts", _moov_file, _nacha_file, _opts) do
    :skip
  end

  defp match_moov_ach_file(key, _moov_file, _nacha_file, _opts) do
    dbg("Missing Key #{key}")
  end

  defp match_moov_ach_file("fileHeader", "fileCreationTime", value, nacha_file, _opts) do
    assert value == nacha_file.file_header.file_creation_time
  end

  defp match_moov_ach_file("fileHeader", "fileCreationDate", value, nacha_file, _opts) do
    assert value == nacha_file.file_header.file_creation_date
  end

  defp match_moov_ach_file("fileHeader", "immediateOrigin", value, nacha_file, _opts) do
    assert value == nacha_file.file_header.immediate_origin
  end

  defp match_moov_ach_file("fileHeader", "immediateDestination", value, nacha_file, _opts) do
    assert value == nacha_file.file_header.immediate_destination
  end

  defp match_moov_ach_file("fileHeader", "fileIDModifier", value, nacha_file, _opts) do
    assert value == nacha_file.file_header.file_id_modifier
  end

  defp match_moov_ach_file("fileHeader", "immediateDestinationName", value, nacha_file, _opts) do
    assert value == nacha_file.file_header.immediate_destination_name
  end

  defp match_moov_ach_file("fileHeader", "immediateOriginName", value, nacha_file, _opts) do
    assert value == nacha_file.file_header.immediate_origin_name
  end

  defp match_moov_ach_file("fileHeader", "id", _, _, _opts) do
    :skip
  end

  defp match_moov_ach_file("fileHeader", file_header_key, _, _, _opts) do
    dbg("Missing Key fileHeader.#{file_header_key}")
  end

  defp match_moov_ach_file("fileControl", "fileCreationDate", value, nacha_file, _opts) do
    assert value == nacha_file.file_control.file_creation_date
  end

  defp match_moov_ach_file("fileControl", "batchCount", value, nacha_file, _opts) do
    assert value == nacha_file.file_control.batch_count
  end

  defp match_moov_ach_file("fileControl", "totalCredit", value, nacha_file, _opts) do
    assert value == nacha_file.file_control.total_credits
  end

  defp match_moov_ach_file("fileControl", "totalDebit", value, nacha_file, _opts) do
    assert value == nacha_file.file_control.total_debits
  end

  defp match_moov_ach_file("fileControl", "blockCount", value, nacha_file, _opts) do
    assert value == nacha_file.file_control.block_count
  end

  defp match_moov_ach_file("fileControl", "entryAddendaCount", value, nacha_file, _opts) do
    assert value == nacha_file.file_control.entry_addenda_count
  end

  defp match_moov_ach_file("fileControl", "entryHash", value, nacha_file, _opts) do
    assert value == nacha_file.file_control.entry_hash
  end

  defp match_moov_ach_file("fileControl", "id", _, _, _opts) do
    :skip
  end

  defp match_moov_ach_file("batches", "offset", _, _, _opts) do
    :skip
  end

  defp match_moov_ach_file(
         "batches" = batches_key,
         "batchControl" = batch_control_key,
         batch_control,
         nacha_file_batch,
         opts
       ) do
    for key <- Map.keys(batch_control) do
      match_moov_ach_file(
        batches_key,
        batch_control_key,
        key,
        batch_control[key],
        nacha_file_batch,
        opts
      )
    end
  end

  defp match_moov_ach_file(
         "batches" = batches_key,
         "batchHeader" = batch_header_key,
         batch_control,
         nacha_file_batch,
         opts
       ) do
    for key <- Map.keys(batch_control) do
      match_moov_ach_file(
        batches_key,
        batch_header_key,
        key,
        batch_control[key],
        nacha_file_batch,
        opts
      )
    end
  end

  defp match_moov_ach_file("batches", batch_key, _, _, _opts) do
    dbg("Missing Key batches.#{batch_key}")
  end

  defp match_moov_ach_file("fileControl", file_control_key, _, _, _opts) do
    dbg("Missing Key fileControl.#{file_control_key}")
  end

  defp match_moov_ach_file(
         "batches",
         "batchHeader",
         "ODFIIdentification",
         value,
         nacha_file_batch,
         _opts
       ) do
    assert value == "#{nacha_file_batch.batch_header.odfi_identification}"
  end

  defp match_moov_ach_file("batches", "batchHeader", "batchNumber", value, nacha_file_batch, _opts) do
    assert value == nacha_file_batch.batch_header.batch_number
  end

  defp match_moov_ach_file(
         "batches",
         "batchHeader",
         "companyEntryDescription",
         value,
         nacha_file_batch,
         _opts
       ) do
    assert value == nacha_file_batch.batch_header.company_entry_description
  end

  defp match_moov_ach_file(
         "batches",
         "batchHeader",
         "companyIdentification",
         value,
         nacha_file_batch,
         _opts
       ) do
    assert value == nacha_file_batch.batch_header.company_identification
  end

  defp match_moov_ach_file(
         "batches",
         "batchHeader",
         "companyName",
         value,
         nacha_file_batch,
         _opts
       ) do
    assert value == nacha_file_batch.batch_header.company_name
  end

  defp match_moov_ach_file(
         "batches",
         "batchHeader",
         "originatorStatusCode",
         value,
         nacha_file_batch,
         _opts
       ) do
    # TODO: Follow up on this one
    assert "#{value}" == nacha_file_batch.batch_header.originator_status_code
  end

  defp match_moov_ach_file(
         "batches",
         "batchHeader",
         "serviceClassCode",
         value,
         nacha_file_batch,
         _opts
       ) do
    assert value == nacha_file_batch.batch_header.service_class_code
  end

  defp match_moov_ach_file(
         "batches",
         "batchHeader",
         "settlementDate",
         value,
         nacha_file_batch,
         _opts
       ) do
    assert value == nacha_file_batch.batch_header.settlement_date
  end

  defp match_moov_ach_file(
         "batches",
         "batchHeader",
         "effectiveEntryDate",
         value,
         nacha_file_batch,
         _opts
       ) do
    assert value == nacha_file_batch.batch_header.effective_entry_date
  end

  defp match_moov_ach_file(
         "batches",
         "batchHeader",
         "standardEntryClassCode",
         value,
         nacha_file_batch,
         _opts
       ) do
    assert value == nacha_file_batch.batch_header.standard_entry_class_code
  end

  defp match_moov_ach_file(
         "batches",
         "batchHeader",
         "id",
         _,
         _,
         _opts
       ) do
    :skip
  end

  defp match_moov_ach_file(
         "batches",
         "batchControl",
         "ODFIIdentification",
         value,
         nacha_file_batch,
         _opts
       ) do
    assert value == nacha_file_batch.batch_control.originating_dfi_identification
  end

  defp match_moov_ach_file(
         "batches",
         "batchControl",
         "companyIdentification",
         value,
         nacha_file_batch,
         _opts
       ) do
    assert value == "#{nacha_file_batch.batch_control.company_identification}"
  end

  defp match_moov_ach_file("batches", "batchControl", "batchNumber", value, nacha_file_batch, _opts) do
    assert value == nacha_file_batch.batch_control.batch_number
  end

  defp match_moov_ach_file(
         "batches",
         "batchControl",
         "entryAddendaCount",
         value,
         nacha_file_batch,
         _opts
       ) do
    assert value == nacha_file_batch.batch_control.entry_addenda_count
  end

  defp match_moov_ach_file("batches", "batchControl", "entryHash", value, nacha_file_batch, _opts) do
    assert value == nacha_file_batch.batch_control.entry_hash
  end

  defp match_moov_ach_file("batches", "batchControl", "serviceClassCode", value, nacha_file_batch, _opts) do
    assert value == nacha_file_batch.batch_control.service_class_code
  end

  defp match_moov_ach_file("batches", "batchControl", "totalCredit", value, nacha_file_batch, _opts) do
    assert value == nacha_file_batch.batch_control.total_credit_entries
  end

  defp match_moov_ach_file("batches", "batchControl", "totalDebit", value, nacha_file_batch, _opts) do
    assert value == nacha_file_batch.batch_control.total_debit_entries
  end

  defp match_moov_ach_file("batches", "batchControl", "id", _, _, _opts) do
    :skip
  end

  #  defp match_moov_ach_file("batches" = key, "entryDetails" = batches_key, batches, nacha_file_batch) do
  #    Enum.with_index(batches, fn entry_detail, index ->
  #      for entry_detail_key <- Map.keys(entry_detail) do
  #        match_moov_ach_file(
  #          key,
  #          batches_key,
  #          entry_detail_key,
  #          entry_detail[entry_detail_key],
  #          Enum.at(nacha_file_batch.entry_details, index)
  #        )
  #      end
  #    end)
  #  end

  #  defp match_moov_ach_file("batches", "batchControl", value, nacha_file_batch) do
  #    raise "Missing batchControl"
  #    assert value == nacha_file_batch.batch_control
  #  end
  #

  #
  #  defp match_moov_ach_file("batches", "entryDetails", "transactionCode", value, nacha_file_batch) do
  #    assert value == nacha_file_batch.transaction_code
  #  end
  #
  #  defp match_moov_ach_file("batches", "entryDetails", entry_detail_key, _, _) do
  #    dbg("Missing Key batches.entryDetails.#{entry_detail_key}")
  #  end

  defp normalize_adv_batch(batch) do
    case batch["advBatchControl"] do
      nil -> batch
      _ -> Map.drop(batch, ["batchControl", "entryDetails"])
    end
  end

  defp normalize_adv_file(moov_file) do
    case moov_file["fileADVControl"] do
      nil -> moov_file
      _ -> Map.drop(moov_file, ["fileControl"])
    end
  end
end

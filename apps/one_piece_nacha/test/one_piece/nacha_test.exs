defmodule OnePiece.NachaTest do
  use ExUnit.Case
  doctest OnePiece.Nacha

  @tag :integration
  test "greets the world" do
    dir_path = "nachas"

    moov_failed_files = [
      "adv-valid.json",
      "pos-invalidEntryDetail.ach",
      "adv-noFileControl.ach",
      "adv-invalidFileControl.ach",
      "iat-invalidAddenda99.ach",
      "iat-invalidAddendaRecordIndicator.ach",
      "iat-invalidAddenda98.ach",
      "iat-invalidAddenda17.ach",
      "201805101354.ach",
      "web-invalidNOCFile.ach",
      "bh-ed-ad-bh-ed-ad-ed-ad.ach",
      "201805101355.ach",
      "adv-invalidBatchEntries.ach",
      "iat-invalidAddenda16.ach",
      "iat-invalidAddenda14.ach",
      "pos-invalidReturnFile.ach",
      "iat-invalidAddenda15.ach",
      "iat-invalidAddenda11.ach",
      "return-PPD-custom-reason-code.ach",
      "ppd-debit-fixedLengthInvalid.ach",
      "iat-batchHeaderErr.ach",
      "iat-invalidAddenda10.ach",
      "iat-invalidAddenda12.ach",
      "adv-return.json",
      "Iat-invalidAddenda13.ach",
      "return-noc.ach",
      "incorrect-sample1.ach",
      "ppd-debit-customTraceNumber.ach",
      "iat-invalidAddenda18.ach",
      "FISERV-ZEROFILE-PIMRET825324_032720_110221.ach",
      "iat-invalidBatchControl.ach",
      "sample1.ach",
      "20110729A.ach",
      "ppd-valid.json",
      "return-no-file-header-control.ach",
      "5.ach",
      "4.ach",
      "0.ach",
      "1.ach",
      "invalid-two-micro-deposits.ach",
      "iat-invalidBatchHeader.ach",
      "3.ach",
      "iat-invalidEntryDetail.ach",
      "2.ach"
    ]

    our_failed_files = [
      "mte-read.ach",
      "short-line.ach",
      "ppd-debit-fixedLength.ach",
      "20110805A.ach",
      "dne-read.ach",
      "flattenBatchesMultipleBatchHeaders.ach"
    ]

    fixtures =
      dir_path
      |> TestSupport.list_all_files()
      |> Enum.reject(&(&1 in moov_failed_files))
      |> Enum.reject(&(&1 in our_failed_files))

    for fixture <- fixtures do
      fixture_path = Path.join(dir_path, fixture)
      nacha_file = TestSupport.read_fixture(fixture_path)

      moov_resp = TestSupport.moov_ach_create_file_from_nacha(Uniq.UUID.uuid4(), nacha_file)
      assert moov_resp["error"] == nil, "exclude fixture: \"#{fixture}\""

      case OnePiece.Nacha.decode_file(nacha_file) do
        {:ok, nacha_file} ->
          TestSupport.assert_match_moov_ach_file(moov_resp["file"], nacha_file, [fixture_path: fixture_path])

        {:error, reason, _, _, _, _} ->
          refute reason, "exclude fixture: \"#{fixture}\" because #{reason}"
      end
    end
  end
end

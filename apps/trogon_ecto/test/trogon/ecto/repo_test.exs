defmodule Trogon.Ecto.RepoTest do
  use ExUnit.Case, async: true

  alias Ecto.Multi
  alias Trogon.Ecto.RepoTestSupport.StubRepo

  setup do
    %{multi: Multi.put(Multi.new(), :account, :value)}
  end

  describe "transact_result/2" do
    test "passes a success through untouched", %{multi: multi} do
      StubRepo.stub_transaction({:ok, %{account: :inserted}})

      assert StubRepo.transact_result(multi) == {:ok, %{account: :inserted}}
    end

    test "passes a success that changed nothing through", %{multi: multi} do
      StubRepo.stub_transaction({:ok, %{}})

      assert StubRepo.transact_result(multi) == {:ok, %{}}
    end

    test "keeps only the value that failed", %{multi: multi} do
      StubRepo.stub_transaction({:error, :account, :too_many, %{profile: :inserted}})

      assert StubRepo.transact_result(multi) == {:error, :too_many}
    end

    test "keeps a failed changeset intact", %{multi: multi} do
      changeset = Ecto.Changeset.cast({%{title: nil}, %{title: :string}}, %{title: 1}, [:title])
      StubRepo.stub_transaction({:error, :account, changeset, %{}})

      assert StubRepo.transact_result(multi) == {:error, changeset}
    end

    test "hands the multi and the options to the repo", %{multi: multi} do
      StubRepo.stub_transaction({:ok, %{}})

      StubRepo.transact_result(multi, timeout: 1_000)

      assert_received {:transaction, ^multi, [timeout: 1_000]}
    end

    test "passes no options when none are given", %{multi: multi} do
      StubRepo.stub_transaction({:ok, %{}})

      StubRepo.transact_result(multi)

      assert_received {:transaction, ^multi, []}
    end

    test "takes a multi and nothing else" do
      for value <- [%{}, fn -> :ok end, {:ok, %{}}] do
        assert_raise FunctionClauseError, fn -> StubRepo.transact_result(value) end
      end
    end
  end
end

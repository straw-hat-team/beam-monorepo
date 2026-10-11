defmodule Trogon.Commanded.TestSupport.Trogon.Commanded.Demo.AccountOpened do
  @moduledoc false

  use Protobuf,
    full_name: "trogon.commanded.demo.AccountOpened",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :id, 1, type: :string
  field :account_number, 2, type: :string, json_name: "accountNumber"
end

defmodule Trogon.Commanded.TestSupport.Trogon.Commanded.Demo.AccountClosed do
  @moduledoc false

  use Protobuf,
    full_name: "trogon.commanded.demo.AccountClosed",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :id, 1, type: :string
end

defmodule Trogon.Commanded.TestSupport.Trogon.Commanded.Demo.TransferInitiated do
  @moduledoc false

  use Protobuf,
    full_name: "trogon.commanded.demo.TransferInitiated",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :id, 1, type: :string
  field :from_account, 2, type: :string, json_name: "fromAccount"
  field :to_account, 3, type: :string, json_name: "toAccount"
  field :amount, 4, type: :int64
end

defmodule Trogon.TypeProvider.TestSupport.Trogon.Typeprovider.Demo.UserCreated do
  @moduledoc false

  use Protobuf,
    full_name: "trogon.typeprovider.demo.UserCreated",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:id, 1, type: :string)
  field(:email, 2, type: :string)
  field(:name, 3, type: :string)
end

defmodule Trogon.TypeProvider.TestSupport.Trogon.Typeprovider.Demo.UserDeleted do
  @moduledoc false

  use Protobuf,
    full_name: "trogon.typeprovider.demo.UserDeleted",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:id, 1, type: :string)
end

defmodule Trogon.TypeProvider.TestSupport.Trogon.Typeprovider.Demo.OrderPlaced do
  @moduledoc false

  use Protobuf,
    full_name: "trogon.typeprovider.demo.OrderPlaced",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:id, 1, type: :string)
  field(:items, 2, repeated: true, type: :string)
end

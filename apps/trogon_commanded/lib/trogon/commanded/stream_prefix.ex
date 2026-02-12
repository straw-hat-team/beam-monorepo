defmodule Trogon.Commanded.StreamPrefix do
  @moduledoc false

  alias Trogon.Commanded.ProtoExtension
  alias TrogonProto.Stream.V1Alpha1.EnumValueOptions

  @proto_extension_tag 870_011
  @proto_extension_name "trogon.stream.v1alpha1.enum_value"
  @default_separator ":"

  @spec resolve(String.t() | nil | {module(), atom()}, Macro.Env.t()) :: String.t() | nil
  def resolve(nil, _caller), do: nil
  def resolve(prefix, _caller) when is_binary(prefix), do: prefix

  def resolve({mod, val}, caller) do
    mod = Macro.expand(mod, caller)

    binary =
      ProtoExtension.find_enum_value_extension!(
        mod,
        val,
        @proto_extension_tag,
        @proto_extension_name
      )

    opts = EnumValueOptions.decode(binary)

    if opts.prefix == "" do
      raise ArgumentError,
            "prefix is required for #{inspect(val)} but was empty."
    end

    separator = if opts.separator, do: opts.separator, else: @default_separator

    opts.prefix <> separator
  end
end

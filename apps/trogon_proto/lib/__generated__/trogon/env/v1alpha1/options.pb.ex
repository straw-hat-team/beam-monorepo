defmodule TrogonProto.Env.V1Alpha1.Decode.Base64.Alphabet do
  @moduledoc """
  Alphabet selects the RFC 4648 alphabet.
  """

  use Protobuf,
    enum: true,
    full_name: "trogon.env.v1alpha1.Decode.Base64.Alphabet",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.EnumDescriptorProto{
      name: "Alphabet",
      value: [
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "ALPHABET_UNSPECIFIED",
          number: 0,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "ALPHABET_STANDARD",
          number: 1,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "ALPHABET_URL_SAFE",
          number: 2,
          options: nil,
          __unknown_fields__: []
        }
      ],
      options: nil,
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:ALPHABET_UNSPECIFIED, 0)
  field(:ALPHABET_STANDARD, 1)
  field(:ALPHABET_URL_SAFE, 2)
end

defmodule TrogonProto.Env.V1Alpha1.Decode.Base64.Padding do
  @moduledoc """
  Padding declares whether `=` padding is expected on the input.
  """

  use Protobuf,
    enum: true,
    full_name: "trogon.env.v1alpha1.Decode.Base64.Padding",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.EnumDescriptorProto{
      name: "Padding",
      value: [
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "PADDING_UNSPECIFIED",
          number: 0,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "PADDING_REQUIRED",
          number: 1,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "PADDING_ABSENT",
          number: 2,
          options: nil,
          __unknown_fields__: []
        }
      ],
      options: nil,
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:PADDING_UNSPECIFIED, 0)
  field(:PADDING_REQUIRED, 1)
  field(:PADDING_ABSENT, 2)
end

defmodule TrogonProto.Env.V1Alpha1.Split do
  @moduledoc """
  Split turns the single environment value into the elements of a repeated
  field.

  It is the only step that changes how many values are in play, which is why
  steps before it see the whole environment value and steps after it run once
  per element.
  """

  use Protobuf,
    full_name: "trogon.env.v1alpha1.Split",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Split",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "delimiter",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "delimiter",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:delimiter, 1, type: :string)
end

defmodule TrogonProto.Env.V1Alpha1.Trim do
  @moduledoc """
  Trim removes leading and trailing characters from a value. Internal
  characters are never affected.

  INVARIANT: exactly one of its oneof fields must be set. An empty `Trim`
  (with `by` unset) is a schema error and must be rejected.
  """

  use Protobuf,
    full_name: "trogon.env.v1alpha1.Trim",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Trim",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "unicode_whitespace",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".google.protobuf.Empty",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "unicodeWhitespace",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "chars",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "chars",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [
        %Google.Protobuf.OneofDescriptorProto{name: "by", options: nil, __unknown_fields__: []}
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  oneof(:by, 0)

  field(:unicode_whitespace, 1,
    type: Google.Protobuf.Empty,
    json_name: "unicodeWhitespace",
    oneof: 0
  )

  field(:chars, 2, type: :string, oneof: 0)
end

defmodule TrogonProto.Env.V1Alpha1.Constraints.ByteSize.Range do
  @moduledoc """
  Range is an inclusive bound. At least one of `min` or `max` must be set,
  and when both are set `min` must be less than or equal to `max`.
  """

  use Protobuf,
    full_name: "trogon.env.v1alpha1.Constraints.ByteSize.Range",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Range",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "min",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_UINT32,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "min",
          proto3_optional: true,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "max",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_UINT32,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 1,
          json_name: "max",
          proto3_optional: true,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [
        %Google.Protobuf.OneofDescriptorProto{name: "_min", options: nil, __unknown_fields__: []},
        %Google.Protobuf.OneofDescriptorProto{name: "_max", options: nil, __unknown_fields__: []}
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:min, 1, proto3_optional: true, type: :uint32)
  field(:max, 2, proto3_optional: true, type: :uint32)
end

defmodule TrogonProto.Env.V1Alpha1.Constraints.ByteSize do
  @moduledoc """
  ByteSize constrains the byte length of a value. For text this is the UTF-8
  byte length, not the character count.

  Only valid on `bytes` and `string` fields. On any other field type it is a
  schema error.

  INVARIANT: exactly one `bound` must be set. An empty `ByteSize` satisfies
  the non-empty `Constraints` rule while declaring no predicate at all, so it
  is a schema error and must be rejected. Left accepted, a `Decode.accept` of
  `{byte_size: {}}` would have nothing to select on and generators would
  diverge on which candidate wins.
  """

  use Protobuf,
    full_name: "trogon.env.v1alpha1.Constraints.ByteSize",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "ByteSize",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "exact",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_UINT32,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "exact",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "range",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.Constraints.ByteSize.Range",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "range",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [
        %Google.Protobuf.DescriptorProto{
          name: "Range",
          field: [
            %Google.Protobuf.FieldDescriptorProto{
              name: "min",
              extendee: nil,
              number: 1,
              label: :LABEL_OPTIONAL,
              type: :TYPE_UINT32,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: 0,
              json_name: "min",
              proto3_optional: true,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "max",
              extendee: nil,
              number: 2,
              label: :LABEL_OPTIONAL,
              type: :TYPE_UINT32,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: 1,
              json_name: "max",
              proto3_optional: true,
              __unknown_fields__: []
            }
          ],
          nested_type: [],
          enum_type: [],
          extension_range: [],
          extension: [],
          options: nil,
          oneof_decl: [
            %Google.Protobuf.OneofDescriptorProto{
              name: "_min",
              options: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.OneofDescriptorProto{
              name: "_max",
              options: nil,
              __unknown_fields__: []
            }
          ],
          reserved_range: [],
          reserved_name: [],
          __unknown_fields__: []
        }
      ],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [
        %Google.Protobuf.OneofDescriptorProto{name: "bound", options: nil, __unknown_fields__: []}
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  oneof(:bound, 0)

  field(:exact, 1, type: :uint32, oneof: 0)
  field(:range, 2, type: TrogonProto.Env.V1Alpha1.Constraints.ByteSize.Range, oneof: 0)
end

defmodule TrogonProto.Env.V1Alpha1.Constraints do
  @moduledoc """
  Constraints declares the accepted shape of a value.

  INVARIANT: at least one field must be set. An empty `Constraints` is a schema
  error and must be rejected.
  """

  use Protobuf,
    full_name: "trogon.env.v1alpha1.Constraints",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Constraints",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "byte_size",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.Constraints.ByteSize",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "byteSize",
          proto3_optional: true,
          __unknown_fields__: []
        }
      ],
      nested_type: [
        %Google.Protobuf.DescriptorProto{
          name: "ByteSize",
          field: [
            %Google.Protobuf.FieldDescriptorProto{
              name: "exact",
              extendee: nil,
              number: 1,
              label: :LABEL_OPTIONAL,
              type: :TYPE_UINT32,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: 0,
              json_name: "exact",
              proto3_optional: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "range",
              extendee: nil,
              number: 2,
              label: :LABEL_OPTIONAL,
              type: :TYPE_MESSAGE,
              type_name: ".trogon.env.v1alpha1.Constraints.ByteSize.Range",
              default_value: nil,
              options: nil,
              oneof_index: 0,
              json_name: "range",
              proto3_optional: nil,
              __unknown_fields__: []
            }
          ],
          nested_type: [
            %Google.Protobuf.DescriptorProto{
              name: "Range",
              field: [
                %Google.Protobuf.FieldDescriptorProto{
                  name: "min",
                  extendee: nil,
                  number: 1,
                  label: :LABEL_OPTIONAL,
                  type: :TYPE_UINT32,
                  type_name: nil,
                  default_value: nil,
                  options: nil,
                  oneof_index: 0,
                  json_name: "min",
                  proto3_optional: true,
                  __unknown_fields__: []
                },
                %Google.Protobuf.FieldDescriptorProto{
                  name: "max",
                  extendee: nil,
                  number: 2,
                  label: :LABEL_OPTIONAL,
                  type: :TYPE_UINT32,
                  type_name: nil,
                  default_value: nil,
                  options: nil,
                  oneof_index: 1,
                  json_name: "max",
                  proto3_optional: true,
                  __unknown_fields__: []
                }
              ],
              nested_type: [],
              enum_type: [],
              extension_range: [],
              extension: [],
              options: nil,
              oneof_decl: [
                %Google.Protobuf.OneofDescriptorProto{
                  name: "_min",
                  options: nil,
                  __unknown_fields__: []
                },
                %Google.Protobuf.OneofDescriptorProto{
                  name: "_max",
                  options: nil,
                  __unknown_fields__: []
                }
              ],
              reserved_range: [],
              reserved_name: [],
              __unknown_fields__: []
            }
          ],
          enum_type: [],
          extension_range: [],
          extension: [],
          options: nil,
          oneof_decl: [
            %Google.Protobuf.OneofDescriptorProto{
              name: "bound",
              options: nil,
              __unknown_fields__: []
            }
          ],
          reserved_range: [],
          reserved_name: [],
          __unknown_fields__: []
        }
      ],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [
        %Google.Protobuf.OneofDescriptorProto{
          name: "_byte_size",
          options: nil,
          __unknown_fields__: []
        }
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:byte_size, 1,
    proto3_optional: true,
    type: TrogonProto.Env.V1Alpha1.Constraints.ByteSize,
    json_name: "byteSize"
  )
end

defmodule TrogonProto.Env.V1Alpha1.Decode.Base64 do
  @moduledoc """
  Base64 decodes the value as RFC 4648 base64.
  """

  use Protobuf,
    full_name: "trogon.env.v1alpha1.Decode.Base64",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Base64",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "alphabet",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_ENUM,
          type_name: ".trogon.env.v1alpha1.Decode.Base64.Alphabet",
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "alphabet",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "padding",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_ENUM,
          type_name: ".trogon.env.v1alpha1.Decode.Base64.Padding",
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "padding",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
      enum_type: [
        %Google.Protobuf.EnumDescriptorProto{
          name: "Alphabet",
          value: [
            %Google.Protobuf.EnumValueDescriptorProto{
              name: "ALPHABET_UNSPECIFIED",
              number: 0,
              options: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.EnumValueDescriptorProto{
              name: "ALPHABET_STANDARD",
              number: 1,
              options: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.EnumValueDescriptorProto{
              name: "ALPHABET_URL_SAFE",
              number: 2,
              options: nil,
              __unknown_fields__: []
            }
          ],
          options: nil,
          reserved_range: [],
          reserved_name: [],
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumDescriptorProto{
          name: "Padding",
          value: [
            %Google.Protobuf.EnumValueDescriptorProto{
              name: "PADDING_UNSPECIFIED",
              number: 0,
              options: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.EnumValueDescriptorProto{
              name: "PADDING_REQUIRED",
              number: 1,
              options: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.EnumValueDescriptorProto{
              name: "PADDING_ABSENT",
              number: 2,
              options: nil,
              __unknown_fields__: []
            }
          ],
          options: nil,
          reserved_range: [],
          reserved_name: [],
          __unknown_fields__: []
        }
      ],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:alphabet, 1, type: TrogonProto.Env.V1Alpha1.Decode.Base64.Alphabet, enum: true)
  field(:padding, 2, type: TrogonProto.Env.V1Alpha1.Decode.Base64.Padding, enum: true)
end

defmodule TrogonProto.Env.V1Alpha1.Decode.Hex do
  @moduledoc """
  Hex decodes the value as base16. Both upper and lower case are accepted.
  """

  use Protobuf,
    full_name: "trogon.env.v1alpha1.Decode.Hex",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Hex",
      field: [],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end
end

defmodule TrogonProto.Env.V1Alpha1.Decode.Utf8 do
  @moduledoc """
  Utf8 takes the value's own bytes with no transformation. It always
  succeeds, so it is only meaningful as the last candidate.
  """

  use Protobuf,
    full_name: "trogon.env.v1alpha1.Decode.Utf8",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Utf8",
      field: [],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end
end

defmodule TrogonProto.Env.V1Alpha1.Decode.Candidate do
  @moduledoc """
  Candidate is one way to read the text.

  INVARIANT: exactly one of its oneof fields must be set. An empty
  `Candidate` (with `as` unset) is a schema error and must be rejected.
  """

  use Protobuf,
    full_name: "trogon.env.v1alpha1.Decode.Candidate",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Candidate",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "base64",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.Decode.Base64",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "base64",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "hex",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.Decode.Hex",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "hex",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "utf8",
          extendee: nil,
          number: 3,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.Decode.Utf8",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "utf8",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [
        %Google.Protobuf.OneofDescriptorProto{name: "as", options: nil, __unknown_fields__: []}
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  oneof(:as, 0)

  field(:base64, 1, type: TrogonProto.Env.V1Alpha1.Decode.Base64, oneof: 0)
  field(:hex, 2, type: TrogonProto.Env.V1Alpha1.Decode.Hex, oneof: 0)
  field(:utf8, 3, type: TrogonProto.Env.V1Alpha1.Decode.Utf8, oneof: 0)
end

defmodule TrogonProto.Env.V1Alpha1.Decode do
  @moduledoc """
  Decode turns text into bytes.

  Environment variables are always text, so a `bytes` field needs a declared
  decoding. Only valid on `bytes` and `string` fields.
  """

  use Protobuf,
    full_name: "trogon.env.v1alpha1.Decode",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Decode",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "any_of",
          extendee: nil,
          number: 1,
          label: :LABEL_REPEATED,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.Decode.Candidate",
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "anyOf",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "accept",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.Constraints",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "accept",
          proto3_optional: true,
          __unknown_fields__: []
        }
      ],
      nested_type: [
        %Google.Protobuf.DescriptorProto{
          name: "Base64",
          field: [
            %Google.Protobuf.FieldDescriptorProto{
              name: "alphabet",
              extendee: nil,
              number: 1,
              label: :LABEL_OPTIONAL,
              type: :TYPE_ENUM,
              type_name: ".trogon.env.v1alpha1.Decode.Base64.Alphabet",
              default_value: nil,
              options: nil,
              oneof_index: nil,
              json_name: "alphabet",
              proto3_optional: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "padding",
              extendee: nil,
              number: 2,
              label: :LABEL_OPTIONAL,
              type: :TYPE_ENUM,
              type_name: ".trogon.env.v1alpha1.Decode.Base64.Padding",
              default_value: nil,
              options: nil,
              oneof_index: nil,
              json_name: "padding",
              proto3_optional: nil,
              __unknown_fields__: []
            }
          ],
          nested_type: [],
          enum_type: [
            %Google.Protobuf.EnumDescriptorProto{
              name: "Alphabet",
              value: [
                %Google.Protobuf.EnumValueDescriptorProto{
                  name: "ALPHABET_UNSPECIFIED",
                  number: 0,
                  options: nil,
                  __unknown_fields__: []
                },
                %Google.Protobuf.EnumValueDescriptorProto{
                  name: "ALPHABET_STANDARD",
                  number: 1,
                  options: nil,
                  __unknown_fields__: []
                },
                %Google.Protobuf.EnumValueDescriptorProto{
                  name: "ALPHABET_URL_SAFE",
                  number: 2,
                  options: nil,
                  __unknown_fields__: []
                }
              ],
              options: nil,
              reserved_range: [],
              reserved_name: [],
              __unknown_fields__: []
            },
            %Google.Protobuf.EnumDescriptorProto{
              name: "Padding",
              value: [
                %Google.Protobuf.EnumValueDescriptorProto{
                  name: "PADDING_UNSPECIFIED",
                  number: 0,
                  options: nil,
                  __unknown_fields__: []
                },
                %Google.Protobuf.EnumValueDescriptorProto{
                  name: "PADDING_REQUIRED",
                  number: 1,
                  options: nil,
                  __unknown_fields__: []
                },
                %Google.Protobuf.EnumValueDescriptorProto{
                  name: "PADDING_ABSENT",
                  number: 2,
                  options: nil,
                  __unknown_fields__: []
                }
              ],
              options: nil,
              reserved_range: [],
              reserved_name: [],
              __unknown_fields__: []
            }
          ],
          extension_range: [],
          extension: [],
          options: nil,
          oneof_decl: [],
          reserved_range: [],
          reserved_name: [],
          __unknown_fields__: []
        },
        %Google.Protobuf.DescriptorProto{
          name: "Hex",
          field: [],
          nested_type: [],
          enum_type: [],
          extension_range: [],
          extension: [],
          options: nil,
          oneof_decl: [],
          reserved_range: [],
          reserved_name: [],
          __unknown_fields__: []
        },
        %Google.Protobuf.DescriptorProto{
          name: "Utf8",
          field: [],
          nested_type: [],
          enum_type: [],
          extension_range: [],
          extension: [],
          options: nil,
          oneof_decl: [],
          reserved_range: [],
          reserved_name: [],
          __unknown_fields__: []
        },
        %Google.Protobuf.DescriptorProto{
          name: "Candidate",
          field: [
            %Google.Protobuf.FieldDescriptorProto{
              name: "base64",
              extendee: nil,
              number: 1,
              label: :LABEL_OPTIONAL,
              type: :TYPE_MESSAGE,
              type_name: ".trogon.env.v1alpha1.Decode.Base64",
              default_value: nil,
              options: nil,
              oneof_index: 0,
              json_name: "base64",
              proto3_optional: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "hex",
              extendee: nil,
              number: 2,
              label: :LABEL_OPTIONAL,
              type: :TYPE_MESSAGE,
              type_name: ".trogon.env.v1alpha1.Decode.Hex",
              default_value: nil,
              options: nil,
              oneof_index: 0,
              json_name: "hex",
              proto3_optional: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "utf8",
              extendee: nil,
              number: 3,
              label: :LABEL_OPTIONAL,
              type: :TYPE_MESSAGE,
              type_name: ".trogon.env.v1alpha1.Decode.Utf8",
              default_value: nil,
              options: nil,
              oneof_index: 0,
              json_name: "utf8",
              proto3_optional: nil,
              __unknown_fields__: []
            }
          ],
          nested_type: [],
          enum_type: [],
          extension_range: [],
          extension: [],
          options: nil,
          oneof_decl: [
            %Google.Protobuf.OneofDescriptorProto{
              name: "as",
              options: nil,
              __unknown_fields__: []
            }
          ],
          reserved_range: [],
          reserved_name: [],
          __unknown_fields__: []
        }
      ],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [
        %Google.Protobuf.OneofDescriptorProto{
          name: "_accept",
          options: nil,
          __unknown_fields__: []
        }
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:any_of, 1,
    repeated: true,
    type: TrogonProto.Env.V1Alpha1.Decode.Candidate,
    json_name: "anyOf"
  )

  field(:accept, 2, proto3_optional: true, type: TrogonProto.Env.V1Alpha1.Constraints)
end

defmodule TrogonProto.Env.V1Alpha1.Step do
  @moduledoc """
  Step is one operation in the pipeline that derives a field value from an
  environment variable.

  INVARIANT: exactly one of its oneof fields must be set. An empty `Step`
  (with `op` unset) is a schema error and must be rejected.
  """

  use Protobuf,
    full_name: "trogon.env.v1alpha1.Step",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Step",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "split",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.Split",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "split",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "trim",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.Trim",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "trim",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "decode",
          extendee: nil,
          number: 3,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.Decode",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "decode",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "require",
          extendee: nil,
          number: 4,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.Constraints",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "require",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [
        %Google.Protobuf.OneofDescriptorProto{name: "op", options: nil, __unknown_fields__: []}
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  oneof(:op, 0)

  field(:split, 1, type: TrogonProto.Env.V1Alpha1.Split, oneof: 0)
  field(:trim, 2, type: TrogonProto.Env.V1Alpha1.Trim, oneof: 0)
  field(:decode, 3, type: TrogonProto.Env.V1Alpha1.Decode, oneof: 0)
  field(:require, 4, type: TrogonProto.Env.V1Alpha1.Constraints, oneof: 0)
end

defmodule TrogonProto.Env.V1Alpha1.EnvVarOption.TagsEntry do
  use Protobuf,
    full_name: "trogon.env.v1alpha1.EnvVarOption.TagsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "TagsEntry",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "key",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "key",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "value",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "value",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: %Google.Protobuf.MessageOptions{
        message_set_wire_format: false,
        no_standard_descriptor_accessor: false,
        deprecated: false,
        map_entry: true,
        deprecated_legacy_json_field_conflicts: nil,
        features: nil,
        uninterpreted_option: [],
        __pb_extensions__: %{},
        __unknown_fields__: []
      },
      oneof_decl: [],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule TrogonProto.Env.V1Alpha1.EnvVarOption do
  @moduledoc """
  EnvVarOption captures metadata about an environment variable field.
  """

  use Protobuf,
    full_name: "trogon.env.v1alpha1.EnvVarOption",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "EnvVarOption",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "visibility",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_ENUM,
          type_name: ".trogon.env.v1alpha1.Visibility",
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "visibility",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "default_value",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "defaultValue",
          proto3_optional: true,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "steps",
          extendee: nil,
          number: 6,
          label: :LABEL_REPEATED,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.Step",
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "steps",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "split_delimiter",
          extendee: nil,
          number: 4,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: %Google.Protobuf.FieldOptions{
            ctype: :STRING,
            packed: nil,
            deprecated: true,
            lazy: false,
            jstype: :JS_NORMAL,
            weak: false,
            unverified_lazy: false,
            debug_redact: false,
            retention: nil,
            targets: [],
            edition_defaults: [],
            features: nil,
            feature_support: nil,
            uninterpreted_option: [],
            __pb_extensions__: %{},
            __unknown_fields__: []
          },
          oneof_index: 1,
          json_name: "splitDelimiter",
          proto3_optional: true,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "trim",
          extendee: nil,
          number: 5,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.Trim",
          default_value: nil,
          options: %Google.Protobuf.FieldOptions{
            ctype: :STRING,
            packed: nil,
            deprecated: true,
            lazy: false,
            jstype: :JS_NORMAL,
            weak: false,
            unverified_lazy: false,
            debug_redact: false,
            retention: nil,
            targets: [],
            edition_defaults: [],
            features: nil,
            feature_support: nil,
            uninterpreted_option: [],
            __pb_extensions__: %{},
            __unknown_fields__: []
          },
          oneof_index: 2,
          json_name: "trim",
          proto3_optional: true,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "tags",
          extendee: nil,
          number: 3,
          label: :LABEL_REPEATED,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.EnvVarOption.TagsEntry",
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "tags",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [
        %Google.Protobuf.DescriptorProto{
          name: "TagsEntry",
          field: [
            %Google.Protobuf.FieldDescriptorProto{
              name: "key",
              extendee: nil,
              number: 1,
              label: :LABEL_OPTIONAL,
              type: :TYPE_STRING,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: nil,
              json_name: "key",
              proto3_optional: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "value",
              extendee: nil,
              number: 2,
              label: :LABEL_OPTIONAL,
              type: :TYPE_STRING,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: nil,
              json_name: "value",
              proto3_optional: nil,
              __unknown_fields__: []
            }
          ],
          nested_type: [],
          enum_type: [],
          extension_range: [],
          extension: [],
          options: %Google.Protobuf.MessageOptions{
            message_set_wire_format: false,
            no_standard_descriptor_accessor: false,
            deprecated: false,
            map_entry: true,
            deprecated_legacy_json_field_conflicts: nil,
            features: nil,
            uninterpreted_option: [],
            __pb_extensions__: %{},
            __unknown_fields__: []
          },
          oneof_decl: [],
          reserved_range: [],
          reserved_name: [],
          __unknown_fields__: []
        }
      ],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [
        %Google.Protobuf.OneofDescriptorProto{
          name: "_default_value",
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.OneofDescriptorProto{
          name: "_split_delimiter",
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.OneofDescriptorProto{name: "_trim", options: nil, __unknown_fields__: []}
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:visibility, 1, type: TrogonProto.Env.V1Alpha1.Visibility, enum: true)
  field(:default_value, 2, proto3_optional: true, type: :string, json_name: "defaultValue")
  field(:steps, 6, repeated: true, type: TrogonProto.Env.V1Alpha1.Step)

  field(:split_delimiter, 4,
    proto3_optional: true,
    type: :string,
    json_name: "splitDelimiter",
    deprecated: true
  )

  field(:trim, 5, proto3_optional: true, type: TrogonProto.Env.V1Alpha1.Trim, deprecated: true)
  field(:tags, 3, repeated: true, type: TrogonProto.Env.V1Alpha1.EnvVarOption.TagsEntry, map: true)
end

defmodule TrogonProto.Env.V1Alpha1.FieldOptions do
  @moduledoc """
  FieldOptions wraps environment variable metadata.
  This wrapper pattern allows attaching environment variable metadata
  to protobuf fields without symbol conflicts (multiple extensions can
  define different message types without collision).

  Use with `google.protobuf.FieldOptions` extension (see below).
  """

  use Protobuf,
    full_name: "trogon.env.v1alpha1.FieldOptions",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "FieldOptions",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "env_var",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.env.v1alpha1.EnvVarOption",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "envVar",
          proto3_optional: true,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [
        %Google.Protobuf.OneofDescriptorProto{
          name: "_env_var",
          options: nil,
          __unknown_fields__: []
        }
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:env_var, 1,
    proto3_optional: true,
    type: TrogonProto.Env.V1Alpha1.EnvVarOption,
    json_name: "envVar"
  )
end

defmodule TrogonProto.Hierarchy.V1Alpha1.NodeId do
  @moduledoc """
  NodeId identifies one node of a tenant's hierarchy.

  A node is a position in the tenant's tree that resources attach to. It is
  untyped on purpose: tenants model their own structure, and words such as
  "project" or "team" are labels on a node rather than kinds the platform
  interprets. Policy attaches to a node and applies to everything at or below
  it, and name resolution starts at a node and walks toward the root.

  Use this message for the `parent` field on any resource that has a position
  in the tree:

    message Agent {
      string agent_id = 1;
      trogon.hierarchy.v1alpha1.NodeId parent = 2;
    }

  The field is named for its role, `parent`, while the type states what the
  role points at. Do not spell the field `parent_id`; the id suffix belongs to
  the type.

  Do not use NodeId for kinship between resources of the same kind, such as a
  session spawned by a session. Kinship uses the other resource's own id type
  in a qualified field, `parent_session`.
  """

  use Protobuf,
    full_name: "trogon.hierarchy.v1alpha1.NodeId",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "NodeId",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "value",
          extendee: nil,
          number: 1,
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
      options: nil,
      oneof_decl: [],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:value, 1, type: :string)
end

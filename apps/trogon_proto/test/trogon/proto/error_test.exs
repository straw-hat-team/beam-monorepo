defmodule Trogon.Proto.ErrorTest do
  use ExUnit.Case, async: true

  alias Trogon.Proto.Error

  describe "extract_template_opts!/1" do
    test "extracts all template fields from proto message" do
      opts = Error.extract_template_opts!(Acme.Test.V1.UserNotFoundError)

      assert Keyword.get(opts, :domain) == "com.acme.users"
      assert Keyword.get(opts, :reason) == "user_not_found"
      assert Keyword.get(opts, :message) == "The requested user was not found"
      assert Keyword.get(opts, :code) == :NOT_FOUND
      assert Keyword.get(opts, :visibility) == :PUBLIC
      assert Keyword.get(opts, :help) == %{links: [%{url: "https://docs.acme.com/users", description: "User API Docs"}]}

      assert Keyword.get(opts, :metadata) == %{
               "resource" => {"user", :PUBLIC},
               "tenant_kind" => {"internal", :PRIVATE}
             }
    end

    test "extracts all template fields when message is provided" do
      opts = Error.extract_template_opts!(Acme.Test.V1.InternalServerError)

      assert Keyword.fetch!(opts, :domain) == "com.acme.system"
      assert Keyword.fetch!(opts, :reason) == "internal_server_error"
      assert Keyword.fetch!(opts, :message) == "An internal server error occurred"
      assert Keyword.fetch!(opts, :code) == :INTERNAL
      assert Keyword.fetch!(opts, :visibility) == :PRIVATE
      refute Keyword.has_key?(opts, :metadata)
    end

    test "raises for message without error extension" do
      assert_raise ArgumentError,
                   ~r/does not have a trogon.error.v1alpha1.message extension/,
                   fn ->
                     Error.extract_template_opts!(Acme.Test.V1.NoExtensionMessage)
                   end
    end

    test "raises when required domain field is missing" do
      assert_raise ArgumentError,
                   ~r/template\.domain must not be empty/,
                   fn ->
                     Error.extract_template_opts!(Acme.Test.V1.MissingDomainError)
                   end
    end

    test "raises when metadata visibility is not explicit" do
      assert_raise ArgumentError,
                   ~r/error visibility must be VISIBILITY_PRIVATE or VISIBILITY_PUBLIC/,
                   fn ->
                     Error.extract_template_opts!(Acme.Test.V1.MissingMetadataVisibilityError)
                   end
    end

    test "raises for message with non-string fields" do
      assert_raise ArgumentError,
                   ~r/must be of type string, got :TYPE_INT32/,
                   fn ->
                     Error.extract_template_opts!(Acme.Test.V1.NonStringFieldError)
                   end
    end
  end

  describe "field_specs/1" do
    test "returns field specs with visibility and value policy" do
      specs = Error.field_specs(Acme.Test.V1.UserNotFoundError)

      user_id_spec = Enum.find(specs, fn {name, _, _, _} -> name == "userId" end)
      assert user_id_spec == {"userId", :user_id, :PUBLIC, nil}

      refute Enum.any?(specs, fn {name, _, _, _} -> name == "internalTrace" end)

      service_spec = Enum.find(specs, fn {name, _, _, _} -> name == "service" end)
      assert service_spec == {"service", :service, :PUBLIC, {:default, "user-api"}}

      region_spec = Enum.find(specs, fn {name, _, _, _} -> name == "region" end)
      assert region_spec == {"region", :region, :PUBLIC, {:fixed, "us-east-1"}}
    end

    test "returns field specs for message without field extensions" do
      specs = Error.field_specs(Acme.Test.V1.NoExtensionMessage)

      assert specs == []
    end
  end
end

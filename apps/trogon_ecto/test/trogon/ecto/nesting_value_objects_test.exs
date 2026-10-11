defmodule Trogon.Ecto.NestingValueObjectsTest do
  @moduledoc """
  Demonstrates the two ways to nest a value object inside another value object,
  and what each does with maps, own-type structs, and foreign structs.

  Fixtures:

    * `TestSupport.MessageOne` — leaf VO: `field :title, :string`.
    * `TestSupport.MessageThree` — nests via `embeds_one :target, MessageOne`
      (the idiomatic "this VO contains another VO" pattern).
    * `TestSupport.BoxWithField` — nests via `field :content, MessageOne`
      (uses MessageOne as a custom `Ecto.Type`, i.e. an atomic column-shaped value).
  """
  use ExUnit.Case, async: true

  alias Trogon.Ecto.TestSupport.{BoxWithField, MessageOne, MessageThree, MessageTwo}

  describe "embeds_one (nested-schema path)" do
    test "accepts a map — Ecto casts it through the embed's changeset" do
      assert {:ok, %MessageThree{target: %MessageOne{title: "hi"}}} =
               MessageThree.new(%{target: %{title: "hi"}})
    end

    test "accepts an own-type struct — trusted as-is, no re-validation (put_embed semantics)" do
      target = %MessageOne{title: "hi"}
      assert {:ok, %MessageThree{target: ^target}} = MessageThree.new(%{target: target})
    end

    test "trusts an own-type struct even when its data would have failed validation" do
      # The struct is taken as-is; the embed's changeset short-circuits to
      # Ecto.Changeset.change/1. VOs are immutable, so a struct that exists
      # is assumed to have been validated when it was constructed.
      target = %MessageOne{title: 123}
      assert {:ok, %MessageThree{target: ^target}} = MessageThree.new(%{target: target})
    end

    test "rejects a foreign struct — Ecto.cast_embed forwards it, our changeset/2 raises" do
      # Ecto's cast_embed does NOT type-check the value it forwards into the
      # embed's changeset/2. We catch the mismatch and raise a descriptive
      # error instead of letting Ecto.Changeset.cast/4 crash with Ecto.CastError.
      assert_raise ArgumentError, ~r/expected attrs to be a map or %Trogon\.Ecto\.TestSupport\.MessageOne\{\}/, fn ->
        MessageThree.new(%{target: %MessageTwo{title: "hi"}})
      end
    end
  end

  describe "field :foo, MyVO (custom Ecto.Type path)" do
    test "accepts a map — Money.cast/1 builds the struct via new/1" do
      assert {:ok, %BoxWithField{content: %MessageOne{title: "hi"}}} =
               BoxWithField.new(%{content: %{title: "hi"}})
    end

    test "accepts an own-type struct — cast/1 short-circuits, no re-validation" do
      content = %MessageOne{title: "hi"}
      assert {:ok, %BoxWithField{content: ^content}} = BoxWithField.new(%{content: content})
    end

    test "rejects a foreign struct — cast/1 surfaces the descriptive error onto the field" do
      assert {:error, changeset} = BoxWithField.new(%{content: %MessageTwo{title: "hi"}})
      assert %{content: [message]} = Trogon.Ecto.TestSupport.errors_on(changeset)
      assert message =~ "expected %Trogon.Ecto.TestSupport.MessageOne{}"
      assert message =~ "got %Trogon.Ecto.TestSupport.MessageTwo{}"
    end

    test "trusts an own-type struct even if it would fail validation (no re-validation)" do
      # MessageOne has no @enforce_keys, so an empty struct is structurally allowed.
      # The point: cast/1 returns {:ok, value} without running changeset/2 against it.
      content = %MessageOne{title: nil}
      assert {:ok, %BoxWithField{content: ^content}} = BoxWithField.new(%{content: content})
    end
  end
end

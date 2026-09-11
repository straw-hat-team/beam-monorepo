defmodule Trogon.Ecto.ChangesetTest do
  use ExUnit.Case, async: true

  alias Trogon.Ecto.TestSupport

  doctest Trogon.Ecto.Changeset

  @types %{title: :string, tags: {:array, :string}, views: :integer}

  defp changeset(attrs, data \\ %{}) do
    data = Map.merge(%{title: nil, tags: nil, views: nil}, data)

    Ecto.Changeset.cast({data, @types}, attrs, Map.keys(@types))
  end

  describe "validate_unset/3" do
    test "passes when the field was never given" do
      assert changeset(%{}) |> Trogon.Ecto.Changeset.validate_unset(:title) |> Map.fetch!(:valid?)
    end

    test "passes when the field is explicitly nil" do
      assert changeset(%{title: nil}) |> Trogon.Ecto.Changeset.validate_unset(:title) |> Map.fetch!(:valid?)
    end

    test "passes when the field is an empty string, as `cast/4` treats it as missing" do
      assert changeset(%{title: ""}) |> Trogon.Ecto.Changeset.validate_unset(:title) |> Map.fetch!(:valid?)
    end

    test "fails when the field has a value" do
      result = changeset(%{title: "hello"}) |> Trogon.Ecto.Changeset.validate_unset(:title)

      refute result.valid?
      assert TestSupport.errors_on(result) == %{title: ["must be blank"]}
    end

    test "fails when the value is only on the data, with no change at all" do
      result = changeset(%{}, %{title: "hello"}) |> Trogon.Ecto.Changeset.validate_unset(:title)

      refute result.valid?
    end

    test "fails for a value Ecto does not consider empty" do
      for attrs <- [%{views: 0}, %{tags: []}] do
        [field] = Map.keys(attrs)

        refute attrs |> changeset() |> Trogon.Ecto.Changeset.validate_unset(field) |> Map.fetch!(:valid?)
      end
    end

    test "passes for a whitespace-only string, which `cast/4` trims to empty" do
      assert changeset(%{title: "  "}) |> Trogon.Ecto.Changeset.validate_unset(:title) |> Map.fetch!(:valid?)
    end

    test "adds :unset validation metadata" do
      result = changeset(%{title: "hello"}) |> Trogon.Ecto.Changeset.validate_unset(:title)

      assert result.errors == [title: {"must be blank", [validation: :unset]}]
    end

    test "takes a custom message" do
      result = changeset(%{title: "hello"}) |> Trogon.Ecto.Changeset.validate_unset(:title, message: "cannot be given")

      assert TestSupport.errors_on(result) == %{title: ["cannot be given"]}
    end

    test "validates every field in a list" do
      result = changeset(%{title: "hello", views: 1}) |> Trogon.Ecto.Changeset.validate_unset([:title, :views, :tags])

      assert TestSupport.errors_on(result) == %{title: ["must be blank"], views: ["must be blank"]}
    end

    test "keeps the change, unlike validate_required/3, so the caller sees what was rejected" do
      result = changeset(%{title: "hello"}) |> Trogon.Ecto.Changeset.validate_unset(:title)

      assert result.changes == %{title: "hello"}
    end

    test "is the exact negation of validate_required/3" do
      for attrs <- [%{}, %{title: nil}, %{title: ""}, %{title: "hello"}] do
        unset? = attrs |> changeset() |> Trogon.Ecto.Changeset.validate_unset(:title) |> Map.fetch!(:valid?)
        required? = attrs |> changeset() |> Ecto.Changeset.validate_required(:title) |> Map.fetch!(:valid?)

        refute unset? == required?
      end
    end

    test "honors a custom :empty_values from cast/4" do
      result =
        {%{tags: nil}, @types}
        |> Ecto.Changeset.cast(%{tags: []}, [:tags], empty_values: [[]])
        |> Trogon.Ecto.Changeset.validate_unset(:tags)

      assert result.valid?
    end

    test "raises for a field the changeset does not know" do
      assert_raise ArgumentError, ~r/unknown field :bogus/, fn ->
        changeset(%{}) |> Trogon.Ecto.Changeset.validate_unset(:bogus)
      end
    end
  end

  describe "field_violations/1" do
    test "is empty for a changeset with no errors" do
      assert Trogon.Ecto.Changeset.field_violations(changeset(%{title: "hello"})) == []
    end

    test "reports the field, the reason, and the interpolated message" do
      result =
        %{title: "hello"}
        |> changeset()
        |> Ecto.Changeset.validate_length(:title, max: 3)
        |> Trogon.Ecto.Changeset.field_violations()

      assert result == [
               %Trogon.Ecto.FieldViolation{
                 field: "title",
                 reason: :max_length,
                 message: "should be at most 3 character(s)",
                 template: "should be at most %{count} character(s)",
                 metadata: [count: 3]
               }
             ]
    end

    test "reports one violation per error on the same field" do
      result =
        %{title: "hello"}
        |> changeset()
        |> Ecto.Changeset.validate_length(:title, max: 3)
        |> Ecto.Changeset.validate_format(:title, ~r/^[0-9]+$/)
        |> Trogon.Ecto.Changeset.field_violations()

      assert Enum.map(result, & &1.reason) == [:format, :max_length]
      assert Enum.map(result, & &1.field) == ["title", "title"]
    end

    test "sorts by field path" do
      result =
        %{title: "hello", views: "many"}
        |> changeset()
        |> Ecto.Changeset.validate_length(:title, max: 3)
        |> Trogon.Ecto.Changeset.field_violations()

      assert Enum.map(result, & &1.field) == ["title", "views"]
    end

    test "interpolates a message whose metadata cannot be a string" do
      result =
        %{}
        |> changeset()
        |> Ecto.Changeset.add_error(:tags, "got %{value}", value: {:a, :b})
        |> Trogon.Ecto.Changeset.field_violations()

      assert result == [
               %Trogon.Ecto.FieldViolation{
                 field: "tags",
                 reason: :unknown,
                 message: "got {:a, :b}",
                 template: "got %{value}",
                 metadata: [value: {:a, :b}]
               }
             ]
    end

    test "leaves a placeholder with no matching metadata alone" do
      result =
        %{}
        |> changeset()
        |> Ecto.Changeset.add_error(:tags, "got %{nothing}")
        |> Trogon.Ecto.Changeset.field_violations()

      assert [%Trogon.Ecto.FieldViolation{message: "got %{nothing}"}] = result
    end

    test "does not interpolate the :type Ecto injects into a cast error" do
      result =
        %{tags: "not a list"}
        |> changeset()
        |> Trogon.Ecto.Changeset.field_violations()

      assert result == [
               %Trogon.Ecto.FieldViolation{
                 field: "tags",
                 reason: :cast,
                 message: "is invalid",
                 template: "is invalid",
                 metadata: []
               }
             ]
    end
  end

  describe "field_violations/1 templates and metadata" do
    test "carries the bindings the template was rendered with" do
      result =
        %{views: 2}
        |> changeset()
        |> Ecto.Changeset.validate_number(:views, greater_than: 5)
        |> Trogon.Ecto.Changeset.field_violations()

      assert [violation] = result
      assert violation.message == "must be greater than 5"
      assert violation.template == "must be greater than %{number}"
      assert violation.metadata == [number: 5]
    end

    test "carries the set an inclusion was checked against" do
      result =
        %{title: "hello"}
        |> changeset()
        |> Ecto.Changeset.validate_inclusion(:title, ["a", "b"])
        |> Trogon.Ecto.Changeset.field_violations()

      assert [%{metadata: [enum: ["a", "b"]]}] = result
    end

    test "carries the name of the constraint that failed" do
      result =
        %{}
        |> changeset()
        |> Ecto.Changeset.add_error(:title, "has already been taken",
          constraint: :unique,
          constraint_name: "titles_pkey"
        )
        |> Trogon.Ecto.Changeset.field_violations()

      assert [%{reason: :unique_constraint, metadata: [constraint_name: "titles_pkey"]}] = result
    end

    test "drops the keys the reason is derived from" do
      result =
        %{}
        |> changeset()
        |> Ecto.Changeset.add_error(:title, "nope",
          validation: :length,
          kind: :max,
          code: :too_long,
          count: 3
        )
        |> Trogon.Ecto.Changeset.field_violations()

      assert [%{reason: :too_long, metadata: [count: 3]}] = result
    end

    test "drops the :type Ecto injects into a cast error" do
      assert [%{metadata: []}] =
               Trogon.Ecto.Changeset.field_violations(changeset(%{views: "many"}))
    end

    test "keeps a derived key the template interpolates" do
      assert {:error, changeset} = TestSupport.MultiPlaceholderMessage.new(%{code: "x"})

      assert [violation] = Trogon.Ecto.Changeset.field_violations(changeset)
      assert violation.message == "2 of list"
      assert violation.template == "%{count} of %{kind}"
      assert violation.metadata == [count: 2, kind: :list]
    end

    test "interpolating the template with the metadata reproduces the message" do
      changesets = [
        changeset(%{views: "many"}),
        Ecto.Changeset.validate_length(changeset(%{title: "hello"}), :title, max: 3),
        Ecto.Changeset.validate_number(changeset(%{views: 2}), :views, greater_than: 5),
        Ecto.Changeset.validate_required(changeset(%{}), [:title]),
        elem(TestSupport.MultiPlaceholderMessage.new(%{code: "x"}), 1),
        elem(TestSupport.InspectedMetadataMessage.new(%{code: "x"}), 1)
      ]

      for changeset <- changesets,
          violation <- Trogon.Ecto.Changeset.field_violations(changeset) do
        assert Trogon.Ecto.ErrorMessage.interpolate({violation.template, violation.metadata}) ==
                 violation.message
      end
    end
  end

  describe "field_violations/1 reasons" do
    test "narrows a length error by its kind" do
      for {opts, reason} <- [{[min: 8], :min_length}, {[max: 3], :max_length}, {[is: 9], :length}] do
        result =
          %{title: "hello"}
          |> changeset()
          |> Ecto.Changeset.validate_length(:title, opts)
          |> Trogon.Ecto.Changeset.field_violations()

        assert [%Trogon.Ecto.FieldViolation{reason: ^reason}] = result
      end
    end

    test "reports a number error by its kind rather than as :number" do
      for {opts, reason} <- [
            {[greater_than: 5], :greater_than},
            {[less_than: 0], :less_than},
            {[equal_to: 7], :equal_to},
            {[not_equal_to: 1], :not_equal_to},
            {[greater_than_or_equal_to: 5], :greater_than_or_equal_to},
            {[less_than_or_equal_to: 0], :less_than_or_equal_to}
          ] do
        result =
          %{views: 1}
          |> changeset()
          |> Ecto.Changeset.validate_number(:views, opts)
          |> Trogon.Ecto.Changeset.field_violations()

        assert [%Trogon.Ecto.FieldViolation{reason: ^reason}] = result
      end
    end

    test "reports the validation for every other validation" do
      cases = [
        {%{}, &Ecto.Changeset.validate_required(&1, [:title]), :required},
        {%{title: "hello"}, &Ecto.Changeset.validate_format(&1, :title, ~r/^[0-9]+$/), :format},
        {%{title: "hello"}, &Ecto.Changeset.validate_inclusion(&1, :title, ["a"]), :inclusion},
        {%{title: "hello"}, &Ecto.Changeset.validate_exclusion(&1, :title, ["hello"]), :exclusion},
        {%{tags: ["b"]}, &Ecto.Changeset.validate_subset(&1, :tags, ["a"]), :subset},
        {%{title: "hello"}, &Trogon.Ecto.Changeset.validate_unset(&1, :title), :unset}
      ]

      for {attrs, validation, reason} <- cases do
        result =
          attrs
          |> changeset()
          |> validation.()
          |> Trogon.Ecto.Changeset.field_violations()

        assert [%Trogon.Ecto.FieldViolation{reason: ^reason}] = result
      end
    end

    test "suffixes a constraint so it cannot be mistaken for a validation" do
      for {constraint, reason} <- [
            {:unique, :unique_constraint},
            {:foreign, :foreign_constraint},
            {:assoc, :assoc_constraint},
            {:no_assoc, :no_assoc_constraint},
            {:check, :check_constraint},
            {:exclusion, :exclusion_constraint}
          ] do
        result =
          %{}
          |> changeset()
          |> Ecto.Changeset.add_error(:title, "is invalid",
            constraint: constraint,
            constraint_name: "some_index"
          )
          |> Trogon.Ecto.Changeset.field_violations()

        assert [%Trogon.Ecto.FieldViolation{reason: ^reason}] = result
      end
    end

    test "keeps validate_exclusion distinct from exclusion_constraint" do
      validation =
        %{title: "hello"}
        |> changeset()
        |> Ecto.Changeset.validate_exclusion(:title, ["hello"])
        |> Trogon.Ecto.Changeset.field_violations()

      constraint =
        %{}
        |> changeset()
        |> Ecto.Changeset.add_error(:title, "is invalid", constraint: :exclusion, constraint_name: "x")
        |> Trogon.Ecto.Changeset.field_violations()

      assert [%{reason: :exclusion}] = validation
      assert [%{reason: :exclusion_constraint}] = constraint
    end

    test "honors an atom :code over anything inferred" do
      result =
        %{}
        |> changeset()
        |> Ecto.Changeset.add_error(:title, "nope", code: :not_allowed, validation: :required)
        |> Trogon.Ecto.Changeset.field_violations()

      assert [%Trogon.Ecto.FieldViolation{reason: :not_allowed}] = result
    end

    test "ignores a :code that is not an atom" do
      result =
        %{}
        |> changeset()
        |> Ecto.Changeset.add_error(:title, "nope", code: "not_allowed", validation: :required)
        |> Trogon.Ecto.Changeset.field_violations()

      assert [%Trogon.Ecto.FieldViolation{reason: :required}] = result
    end

    test "is :unknown for an error with no metadata to go on" do
      result =
        %{}
        |> changeset()
        |> Ecto.Changeset.add_error(:title, "nope")
        |> Trogon.Ecto.Changeset.field_violations()

      assert [%Trogon.Ecto.FieldViolation{reason: :unknown}] = result
    end
  end

  describe "field_violations/1 with nested changesets" do
    test "reports an embed given the wrong shape on the parent field" do
      assert {:error, changeset} = TestSupport.MessageThree.new(%{target: "not a map"})

      assert Trogon.Ecto.Changeset.field_violations(changeset) == [
               %Trogon.Ecto.FieldViolation{
                 field: "target",
                 reason: :embed,
                 message: "is invalid",
                 template: "is invalid",
                 metadata: []
               }
             ]
    end

    test "indexes a member of a collection" do
      assert {:error, changeset} =
               TestSupport.MessageFour.new(%{targets: [%{}, %{target: %{}}]})

      assert Trogon.Ecto.Changeset.field_violations(changeset) == [
               %Trogon.Ecto.FieldViolation{
                 field: "targets[0].target",
                 reason: :required,
                 message: "can't be blank",
                 template: "can't be blank",
                 metadata: []
               }
             ]
    end

    test "traverses a polymorphic embed" do
      assert {:error, changeset} =
               TestSupport.NotificationWithPolymorphicEmbed.new(%{
                 title: "hello",
                 content: %{__type__: "email"}
               })

      assert Trogon.Ecto.Changeset.field_violations(changeset) == [
               %Trogon.Ecto.FieldViolation{
                 field: "content.body",
                 reason: :required,
                 message: "can't be blank",
                 template: "can't be blank",
                 metadata: []
               },
               %Trogon.Ecto.FieldViolation{
                 field: "content.subject",
                 reason: :required,
                 message: "can't be blank",
                 template: "can't be blank",
                 metadata: []
               }
             ]
    end

    test "indexes against the collection the caller sent, not the one Ecto traverses" do
      data = %TestSupport.Basket{
        items: [
          %TestSupport.Basket.Item{id: "a", sku: "dropped"},
          %TestSupport.Basket.Item{id: "b", sku: "kept"}
        ]
      }

      changeset = TestSupport.Basket.changeset(data, %{items: [%{id: "b", sku: nil}]})

      assert Ecto.Changeset.traverse_errors(changeset, & &1) == %{
               items: [%{}, %{sku: [{"can't be blank", [validation: :required]}]}]
             }

      assert Trogon.Ecto.Changeset.field_violations(changeset) == [
               %Trogon.Ecto.FieldViolation{
                 field: "items[0].sku",
                 reason: :required,
                 message: "can't be blank",
                 template: "can't be blank",
                 metadata: []
               }
             ]
    end
  end
end

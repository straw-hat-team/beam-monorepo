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
end

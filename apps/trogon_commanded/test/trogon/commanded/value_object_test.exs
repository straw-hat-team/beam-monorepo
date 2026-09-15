defmodule Trogon.Commanded.ValueObjectTest do
  use ExUnit.Case, async: true
  doctest Trogon.Commanded.ValueObject

  describe "new/1" do
    test "overriding validate/2" do
      assert {:ok, %Trogon.Commanded.TestSupport.TransferableMoney{amount: 1, currency: :USD}} =
               Trogon.Commanded.TestSupport.TransferableMoney.new(%{amount: 1, currency: :USD})

      assert {:error, changeset} = Trogon.Commanded.TestSupport.TransferableMoney.new(%{amount: 0, currency: :USD})
      assert %{amount: ["must be greater than 0"]} = Trogon.Commanded.TestSupport.errors_on(changeset)
    end

    test "creates a struct" do
      assert {:ok, %Trogon.Commanded.TestSupport.MessageOne{title: nil}} =
               Trogon.Commanded.TestSupport.MessageOne.new(%{})
    end

    test "validates a key enforce" do
      assert {:error, changeset} = Trogon.Commanded.TestSupport.MessageTwo.new(%{})
      assert %{title: ["can't be blank"]} = Trogon.Commanded.TestSupport.errors_on(changeset)
    end

    test "validates a key enforce for embed fields" do
      assert {:error, changeset} = Trogon.Commanded.TestSupport.MessageThree.new(%{})
      assert %{target: ["can't be blank"]} = Trogon.Commanded.TestSupport.errors_on(changeset)
    end

    test "validates casting embed fields" do
      assert {:ok,
              %Trogon.Commanded.TestSupport.MessageThree{
                target: %Trogon.Commanded.TestSupport.MessageOne{title: "Hello, World!"}
              }} =
               Trogon.Commanded.TestSupport.MessageThree.new(%{target: %{title: "Hello, World!"}})
    end

    test "casting structs" do
      assert {:ok,
              %Trogon.Commanded.TestSupport.MessageThree{
                target: %Trogon.Commanded.TestSupport.MessageOne{title: "Hello, World!"}
              }} =
               Trogon.Commanded.TestSupport.MessageThree.new(%{
                 target: %Trogon.Commanded.TestSupport.MessageOne{title: "Hello, World!"}
               })

      assert {:ok,
              %Trogon.Commanded.TestSupport.MessageFour{
                targets: [
                  %Trogon.Commanded.TestSupport.MessageThree{
                    target: %Trogon.Commanded.TestSupport.MessageOne{title: "Hello, World!"}
                  }
                ]
              }} =
               Trogon.Commanded.TestSupport.MessageFour.new(%{
                 targets: [
                   Trogon.Commanded.TestSupport.MessageThree.new!(%{
                     target: Trogon.Commanded.TestSupport.MessageOne.new!(%{title: "Hello, World!"})
                   })
                 ]
               })
    end

    test "validates casting embed fields with a wrong value" do
      assert {:error, changeset} = Trogon.Commanded.TestSupport.MessageThree.new(%{target: "a wrong value"})
      assert %{target: ["is invalid"]} = Trogon.Commanded.TestSupport.errors_on(changeset)
    end
  end

  describe "new!/1" do
    test "raises an error when a validation fails" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        Trogon.Commanded.TestSupport.MessageTwo.new!(%{})
      end
    end
  end

  describe "cast/1" do
    test "casts a struct" do
      assert {:ok, message} =
               Trogon.Commanded.TestSupport.MessageOne.cast(%Trogon.Commanded.TestSupport.MessageOne{
                 title: "Hello, World!"
               })

      assert message.title == "Hello, World!"
    end

    test "casts a map" do
      assert {:ok, message} = Trogon.Commanded.TestSupport.MessageOne.cast(%{title: "Hello, World!"})
      assert message.title == "Hello, World!"
    end

    test "casts a map with a wrong value" do
      assert :error = Trogon.Commanded.TestSupport.MessageOne.cast(%{title: 1})
    end

    test "casts an invalid input" do
      assert :error = Trogon.Commanded.TestSupport.MessageOne.cast(1)
    end
  end

  describe "load/1" do
    test "loads a map" do
      assert {:ok, message} = Trogon.Commanded.TestSupport.MessageOne.load(%{title: "Hello, World!"})
      assert message.title == "Hello, World!"
    end

    test "loads a struct" do
      assert {:ok, message} =
               Trogon.Commanded.TestSupport.MessageOne.load(%Trogon.Commanded.TestSupport.MessageOne{
                 title: "Hello, World!"
               })

      assert message.title == "Hello, World!"
    end

    test "loads an invalid input" do
      assert :error = Trogon.Commanded.TestSupport.MessageOne.load(1)
    end
  end

  describe "dump/1" do
    test "dumps a struct" do
      assert {:ok, %{title: "Hello, World!"}} =
               Trogon.Commanded.TestSupport.MessageOne.dump(%Trogon.Commanded.TestSupport.MessageOne{
                 title: "Hello, World!"
               })
    end

    test "dumps an invalid input" do
      assert :error = Trogon.Commanded.TestSupport.MessageOne.dump(1)
    end
  end

  describe "changeset/2" do
    test "validates the struct" do
      assert {:error, changeset} = Trogon.Commanded.TestSupport.MyValueOject.new(%{amount: 0})
      assert %{amount: ["must be greater than 0"]} = Trogon.Commanded.TestSupport.errors_on(changeset)
    end
  end

  describe "polymorphic_embed support" do
    test "creates a value object with polymorphic_embeds_one email content" do
      attrs = %{
        title: "Welcome Email",
        content: %{
          __type__: :email,
          subject: "Welcome to our platform",
          body: "Thank you for joining us!"
        }
      }

      assert {:ok, notification} = Trogon.Commanded.TestSupport.NotificationWithPolymorphicEmbed.new(attrs)
      assert notification.title == "Welcome Email"
      assert notification.content.__struct__ == Trogon.Commanded.TestSupport.EmailContent
      assert notification.content.subject == "Welcome to our platform"
      assert notification.content.body == "Thank you for joining us!"
    end

    test "creates a value object with polymorphic_embeds_one sms content" do
      attrs = %{
        title: "SMS Notification",
        content: %{
          __type__: :sms,
          message: "Your verification code is 123456",
          phone: "+1234567890"
        }
      }

      assert {:ok, notification} = Trogon.Commanded.TestSupport.NotificationWithPolymorphicEmbed.new(attrs)
      assert notification.title == "SMS Notification"
      assert notification.content.__struct__ == Trogon.Commanded.TestSupport.SmsContent
      assert notification.content.message == "Your verification code is 123456"
      assert notification.content.phone == "+1234567890"
    end

    test "validates required fields for polymorphic_embeds_one" do
      attrs = %{
        title: "Invalid Notification",
        content: %{
          __type__: :email,
          subject: "Missing body"
        }
      }

      assert {:error, changeset} = Trogon.Commanded.TestSupport.NotificationWithPolymorphicEmbed.new(attrs)
      refute changeset.valid?
      assert %{content: %{body: ["can't be blank"]}} = Trogon.Commanded.TestSupport.errors_on(changeset)
    end

    test "validates required polymorphic_embeds_one field" do
      attrs = %{title: "Missing Content"}

      assert {:error, changeset} = Trogon.Commanded.TestSupport.NotificationWithPolymorphicEmbed.new(attrs)
      assert %{content: ["can't be blank"]} = Trogon.Commanded.TestSupport.errors_on(changeset)
    end

    test "creates a value object with polymorphic_embeds_many" do
      attrs = %{
        title: "Multi-channel Message",
        contents: [
          %{
            __type__: :email,
            subject: "Email notification",
            body: "This is an email"
          },
          %{
            __type__: :sms,
            message: "This is an SMS",
            phone: "+1234567890"
          }
        ]
      }

      assert {:ok, message} = Trogon.Commanded.TestSupport.MessageWithMultiplePolymorphicEmbeds.new(attrs)
      assert message.title == "Multi-channel Message"
      assert length(message.contents) == 2

      [email_content, sms_content] = message.contents
      assert email_content.__struct__ == Trogon.Commanded.TestSupport.EmailContent
      assert email_content.subject == "Email notification"
      assert email_content.body == "This is an email"

      assert sms_content.__struct__ == Trogon.Commanded.TestSupport.SmsContent
      assert sms_content.message == "This is an SMS"
      assert sms_content.phone == "+1234567890"
    end

    test "validates required fields for polymorphic_embeds_many" do
      attrs = %{
        title: "Invalid Multi-channel Message",
        contents: [
          %{
            __type__: :email,
            subject: "Valid email",
            body: "This is valid"
          },
          %{
            __type__: :sms,
            message: "Missing phone number"
          }
        ]
      }

      assert {:error, changeset} = Trogon.Commanded.TestSupport.MessageWithMultiplePolymorphicEmbeds.new(attrs)
      refute changeset.valid?
      assert %{contents: [%{}, %{phone: ["can't be blank"]}]} = Trogon.Commanded.TestSupport.errors_on(changeset)
    end

    test "allows empty polymorphic_embeds_many when not required" do
      attrs = %{title: "Missing Contents"}

      assert {:ok, result} = Trogon.Commanded.TestSupport.MessageWithMultiplePolymorphicEmbeds.new(attrs)
      assert result.title == "Missing Contents"
      assert result.contents == []
    end

    test "handles unknown polymorphic type" do
      attrs = %{
        title: "Unknown Type",
        content: %{
          __type__: :unknown_type,
          data: "some data"
        }
      }

      assert_raise RuntimeError, ~r/could not infer polymorphic embed/, fn ->
        Trogon.Commanded.TestSupport.NotificationWithPolymorphicEmbed.new(attrs)
      end
    end

    test "casts polymorphic embed with map data" do
      attrs = %{
        title: "Map Content",
        content: %{
          __type__: :email,
          subject: "Test Subject",
          body: "Test Body"
        }
      }

      assert {:ok, notification} = Trogon.Commanded.TestSupport.NotificationWithPolymorphicEmbed.new(attrs)
      assert notification.title == "Map Content"
      assert notification.content.__struct__ == Trogon.Commanded.TestSupport.EmailContent
      assert notification.content.subject == "Test Subject"
      assert notification.content.body == "Test Body"
    end
  end
end

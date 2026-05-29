defmodule Trogon.Ecto.ValueObjectTest do
  use ExUnit.Case, async: true
  alias Trogon.Ecto.TestSupport
  doctest Trogon.Ecto.ValueObject

  describe "new/1" do
    test "overriding validate/2" do
      assert {:ok, %TestSupport.TransferableMoney{amount: 1, currency: :USD}} =
               TestSupport.TransferableMoney.new(%{amount: 1, currency: :USD})

      assert {:error, changeset} = TestSupport.TransferableMoney.new(%{amount: 0, currency: :USD})
      assert %{amount: ["must be greater than 0"]} = TestSupport.errors_on(changeset)
    end

    test "creates a struct" do
      assert {:ok, %TestSupport.MessageOne{title: nil}} = TestSupport.MessageOne.new(%{})
    end

    test "validates a key enforce" do
      assert {:error, changeset} = TestSupport.MessageTwo.new(%{})
      assert %{title: ["can't be blank"]} = TestSupport.errors_on(changeset)
    end

    test "validates a key enforce for embed fields" do
      assert {:error, changeset} = TestSupport.MessageThree.new(%{})
      assert %{target: ["can't be blank"]} = TestSupport.errors_on(changeset)
    end

    test "validates casting embed fields" do
      assert {:ok, %TestSupport.MessageThree{target: %TestSupport.MessageOne{title: "Hello, World!"}}} =
               TestSupport.MessageThree.new(%{target: %{title: "Hello, World!"}})
    end

    test "casting structs" do
      assert {:ok, %TestSupport.MessageThree{target: %TestSupport.MessageOne{title: "Hello, World!"}}} =
               TestSupport.MessageThree.new(%{target: %TestSupport.MessageOne{title: "Hello, World!"}})

      assert {:ok,
              %TestSupport.MessageFour{
                targets: [%TestSupport.MessageThree{target: %TestSupport.MessageOne{title: "Hello, World!"}}]
              }} =
               TestSupport.MessageFour.new(%{
                 targets: [
                   TestSupport.MessageThree.new!(%{target: TestSupport.MessageOne.new!(%{title: "Hello, World!"})})
                 ]
               })
    end

    test "validates casting embed fields with a wrong value" do
      assert {:error, changeset} = TestSupport.MessageThree.new(%{target: "a wrong value"})
      assert %{target: ["is invalid"]} = TestSupport.errors_on(changeset)
    end

    test "returns an own-type struct unchanged" do
      message = %TestSupport.MessageOne{title: "x"}
      assert {:ok, ^message} = TestSupport.MessageOne.new(message)
    end

    test "raises ArgumentError on a foreign struct" do
      assert_raise ArgumentError,
                   ~r/expected attrs to be a map or %Trogon\.Ecto\.TestSupport\.MessageOne\{\}/,
                   fn ->
                     TestSupport.MessageOne.new(%TestSupport.MessageTwo{title: "x"})
                   end
    end
  end

  describe "new!/1" do
    test "raises an error when a validation fails" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        TestSupport.MessageTwo.new!(%{})
      end
    end

    test "returns an own-type struct unchanged" do
      message = %TestSupport.MessageOne{title: "x"}
      assert ^message = TestSupport.MessageOne.new!(message)
    end

    test "raises ArgumentError on a foreign struct" do
      assert_raise ArgumentError,
                   ~r/expected attrs to be a map or %Trogon\.Ecto\.TestSupport\.MessageOne\{\}/,
                   fn ->
                     TestSupport.MessageOne.new!(%TestSupport.MessageTwo{title: "x"})
                   end
    end
  end

  describe "cast/1" do
    test "casts a struct of the same type" do
      assert {:ok, message} = TestSupport.MessageOne.cast(%TestSupport.MessageOne{title: "Hello, World!"})
      assert message.title == "Hello, World!"
    end

    test "rejects a foreign struct with a descriptive error" do
      assert {:error, [message: message]} =
               TestSupport.MessageOne.cast(%TestSupport.MessageTwo{title: "Hello, World!"})

      assert message =~ "expected %Trogon.Ecto.TestSupport.MessageOne{}"
      assert message =~ "got %Trogon.Ecto.TestSupport.MessageTwo{}"
    end

    test "casts a map" do
      assert {:ok, message} = TestSupport.MessageOne.cast(%{title: "Hello, World!"})
      assert message.title == "Hello, World!"
    end

    test "surfaces a message when a map fails to cast" do
      assert {:error, [message: "is invalid"]} = TestSupport.MessageOne.cast(%{title: 1})
    end

    test "casts an invalid input" do
      assert :error = TestSupport.MessageOne.cast(1)
    end
  end

  describe "load/1" do
    test "loads a map" do
      assert {:ok, message} = TestSupport.MessageOne.load(%{title: "Hello, World!"})
      assert message.title == "Hello, World!"
    end

    test "loads a struct of the same type" do
      assert {:ok, message} = TestSupport.MessageOne.load(%TestSupport.MessageOne{title: "Hello, World!"})
      assert message.title == "Hello, World!"
    end

    test "rejects a foreign struct" do
      assert :error = TestSupport.MessageOne.load(%TestSupport.MessageTwo{title: "Hello, World!"})
    end

    test "loads an invalid input" do
      assert :error = TestSupport.MessageOne.load(1)
    end

    test "loads data that would fail business validation" do
      assert {:ok, %TestSupport.TransferableMoney{amount: -5, currency: :USD}} =
               TestSupport.TransferableMoney.load(%{"amount" => -5, "currency" => "USD"})
    end
  end

  describe "dump/1" do
    test "dumps a struct" do
      assert {:ok, %{title: "Hello, World!"}} =
               TestSupport.MessageOne.dump(%TestSupport.MessageOne{title: "Hello, World!"})
    end

    test "dumps an invalid input" do
      assert :error = TestSupport.MessageOne.dump(1)
    end

    test "recursively dumps nested value object structs into plain maps" do
      box = %TestSupport.BoxWithField{content: %TestSupport.MessageOne{title: "hi"}}
      assert {:ok, dumped} = TestSupport.BoxWithField.dump(box)
      refute is_struct(dumped.content)
      assert dumped.content == %{title: "hi"}
    end
  end

  describe "changeset/2" do
    test "validates the struct" do
      assert {:error, changeset} = TestSupport.MyValueObject.new(%{amount: 0})
      assert %{amount: ["must be greater than 0"]} = TestSupport.errors_on(changeset)
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

      assert {:ok, notification} = TestSupport.NotificationWithPolymorphicEmbed.new(attrs)
      assert notification.title == "Welcome Email"
      assert notification.content.__struct__ == TestSupport.EmailContent
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

      assert {:ok, notification} = TestSupport.NotificationWithPolymorphicEmbed.new(attrs)
      assert notification.title == "SMS Notification"
      assert notification.content.__struct__ == TestSupport.SmsContent
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

      assert {:error, changeset} = TestSupport.NotificationWithPolymorphicEmbed.new(attrs)
      refute changeset.valid?
      assert %{content: %{body: ["can't be blank"]}} = TestSupport.errors_on(changeset)
    end

    test "validates required polymorphic_embeds_one field" do
      attrs = %{title: "Missing Content"}

      assert {:error, changeset} = TestSupport.NotificationWithPolymorphicEmbed.new(attrs)
      assert %{content: ["can't be blank"]} = TestSupport.errors_on(changeset)
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

      assert {:ok, message} = TestSupport.MessageWithMultiplePolymorphicEmbeds.new(attrs)
      assert message.title == "Multi-channel Message"
      assert length(message.contents) == 2

      [email_content, sms_content] = message.contents
      assert email_content.__struct__ == TestSupport.EmailContent
      assert email_content.subject == "Email notification"
      assert email_content.body == "This is an email"

      assert sms_content.__struct__ == TestSupport.SmsContent
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

      assert {:error, changeset} = TestSupport.MessageWithMultiplePolymorphicEmbeds.new(attrs)
      refute changeset.valid?
      assert %{contents: [%{}, %{phone: ["can't be blank"]}]} = TestSupport.errors_on(changeset)
    end

    test "rejects empty required polymorphic_embeds_many" do
      attrs = %{title: "Missing Contents"}

      assert {:error, changeset} = TestSupport.MessageWithMultiplePolymorphicEmbeds.new(attrs)
      assert %{contents: ["can't be blank"]} = TestSupport.errors_on(changeset)
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
        TestSupport.NotificationWithPolymorphicEmbed.new(attrs)
      end
    end

    test "round-trips polymorphic_embeds_one through dump and load" do
      {:ok, notification} =
        TestSupport.NotificationWithPolymorphicEmbed.new(%{
          title: "Welcome Email",
          content: %{
            __type__: :email,
            subject: "Hello",
            body: "World"
          }
        })

      assert {:ok, dumped} = TestSupport.NotificationWithPolymorphicEmbed.dump(notification)
      assert {:ok, loaded} = TestSupport.NotificationWithPolymorphicEmbed.load(dumped)

      assert loaded.title == "Welcome Email"
      assert loaded.content.__struct__ == TestSupport.EmailContent
      assert loaded.content.subject == "Hello"
      assert loaded.content.body == "World"
    end

    test "round-trips polymorphic_embeds_many through dump and load" do
      {:ok, message} =
        TestSupport.MessageWithMultiplePolymorphicEmbeds.new(%{
          title: "Multi",
          contents: [
            %{__type__: :email, subject: "s", body: "b"},
            %{__type__: :sms, message: "m", phone: "+1"}
          ]
        })

      assert {:ok, dumped} = TestSupport.MessageWithMultiplePolymorphicEmbeds.dump(message)
      assert {:ok, loaded} = TestSupport.MessageWithMultiplePolymorphicEmbeds.load(dumped)

      assert loaded.title == "Multi"
      assert [email, sms] = loaded.contents
      assert email.__struct__ == TestSupport.EmailContent
      assert email.subject == "s"
      assert email.body == "b"
      assert sms.__struct__ == TestSupport.SmsContent
      assert sms.message == "m"
      assert sms.phone == "+1"
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

      assert {:ok, notification} = TestSupport.NotificationWithPolymorphicEmbed.new(attrs)
      assert notification.title == "Map Content"
      assert notification.content.__struct__ == TestSupport.EmailContent
      assert notification.content.subject == "Test Subject"
      assert notification.content.body == "Test Body"
    end
  end
end

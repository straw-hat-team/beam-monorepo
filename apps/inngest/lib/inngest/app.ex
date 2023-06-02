defmodule Inngest.App do
  defmacro __using__(opts) do
    app_name = Keyword.fetch!(opts, :app_name)

    quote do
      import Inngest.App, only: [register_function: 1]

      @before_compile Inngest.App

      Module.register_attribute(__MODULE__, :functions, accumulate: true)

      #      @behaviour Inngest

      def app_name do
        unquote(app_name)
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def functions, do: @functions
      unquote(Inngest.App.__add_func_handler__())
    end
  end

  defmacro register_function(registration) do
    quote bind_quoted: [registration: registration] do
      Inngest.App.__register_function__(
        __MODULE__,
        registration
      )
    end
  end

  # TODO: add the concept of slug to count for ID vs. Name
  def __add_func_handler__() do
    quote unquote: false do
      for registration <- @functions do
        def get_registration(unquote(registration.name)) do
          {:ok, unquote(registration.name)}
        end
      end

      def get_registration(_registration) do
        {:error, :not_found}
      end
    end
  end

  def __register_function__(mod, registration) do
    case find_mapping_by_name(mod, registration) do
      nil ->
        add_mapping(mod, registration)

      {registration} ->
        raise ArgumentError, "#{inspect(registration.name)} already registered"
    end
  end

  defp add_mapping(mod, registration) do
    Module.put_attribute(mod, :functions, registration)
  end

  defp find_mapping_by_name(mod, registration) do
    mod
    |> Module.get_attribute(:functions)
    |> Enum.find(&(&1.name == registration.name))
  end
end

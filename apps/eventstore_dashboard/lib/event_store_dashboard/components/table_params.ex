defmodule EventStoreDashboard.Components.TableParams do
  @moduledoc false

  @default_limit 50
  @valid_limits [50, 100, 500, 1000, 5000]

  def parse_limit(%{"limit" => value}) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n in @valid_limits -> n
      _ -> @default_limit
    end
  end

  def parse_limit(_params), do: @default_limit

  def parse_search(%{"search" => value}) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def parse_search(_params), do: nil

  def parse_sort_dir(%{"sort_dir" => "asc"}, _default), do: :asc
  def parse_sort_dir(%{"sort_dir" => "desc"}, _default), do: :desc
  def parse_sort_dir(_params, default), do: default

  def parse_sort_by(%{"sort_by" => value}, allowed, default) when is_binary(value) do
    case value in allowed do
      true -> String.to_atom(value)
      false -> default
    end
  end

  def parse_sort_by(_params, _allowed, default), do: default
end

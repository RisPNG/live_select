defmodule LiveSelectTest do
  use ExUnit.Case, async: true

  doctest LiveSelect, import: true

  test "decodes submitted composite values with Phoenix's configured JSON library" do
    coordinates = [-74.00597, 40.71427]
    city = %{"name" => "New York", "coordinates" => coordinates}

    assert LiveSelect.decode(JSON.encode!(city)) == city

    assert LiveSelect.decode(Enum.map([coordinates, city], &JSON.encode!/1)) == [
             coordinates,
             city
           ]
  end

  test "decodes empty fields and JSON scalar values" do
    assert LiveSelect.decode(nil) == []
    assert LiveSelect.decode([]) == []
    assert LiveSelect.decode("") == nil
    assert LiveSelect.decode("null") == nil
    assert LiveSelect.decode("42") == 42
    assert LiveSelect.decode("true") == true
    assert LiveSelect.decode(~s("MY")) == "MY"
  end

  test "reports invalid JSON instead of silently changing submitted values" do
    assert_raise JSON.DecodeError, fn -> LiveSelect.decode("{invalid") end
  end

  test "ignores native empty multiple-selection placeholders when decoding submitted values" do
    city = %{"name" => "Berlin", "coordinates" => [13.41053, 52.52437]}

    assert LiveSelect.decode([""]) == []
    assert LiveSelect.decode(["", JSON.encode!(city), ""]) == [city]
    assert LiveSelect.decode(["", ~s(""), ""]) == [""]
  end
end

defmodule LiveSelect.ClassUtilTest do
  use ExUnit.Case, async: true

  doctest LiveSelect.ClassUtil, import: true

  test "extends theme classes without duplicates or absent conditional classes" do
    assert LiveSelect.ClassUtil.extend(
             [nil, "rounded", "border", "rounded"],
             [nil, "!rounded", "border", "shadow", "shadow"]
           ) == ["border", "shadow"]
  end

  test "can replace a default class after removing it" do
    assert LiveSelect.ClassUtil.extend(["rounded", "border"], ["!rounded", "rounded-lg"]) ==
             ["border", "rounded-lg"]
  end
end

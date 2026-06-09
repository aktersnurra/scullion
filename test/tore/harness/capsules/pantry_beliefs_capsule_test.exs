defmodule Tore.Harness.Capsules.PantryBeliefsCapsuleTest do
  use Tore.DataCase, async: false

  alias Tore.Harness.Capsules.PantryBeliefsCapsule, as: Capsule

  @ctx %{household_id: 1, plan_stream_id: "plan:2026-06-08", week_start: ~D[2026-06-08]}

  test "build/1 caps names at 20 but keeps the full total" do
    for n <- 1..25, do: Tore.Pantry.add_item(%{name: "item #{n}", quantity: 1})

    capsule = Capsule.build(@ctx)
    assert length(capsule.names) == 20
    assert capsule.total == 25
  end

  test "to_prompt/1 lists names and the overflow count" do
    for n <- 1..25, do: Tore.Pantry.add_item(%{name: "item #{n}", quantity: 1})

    prompt = @ctx |> Capsule.build() |> Capsule.to_prompt()
    assert prompt =~ "Pantry has:"
    assert prompt =~ "and 5 more"
    assert String.ends_with?(prompt, ".")
  end

  test "to_prompt/1 has no overflow clause at or below 20 items" do
    for n <- 1..3, do: Tore.Pantry.add_item(%{name: "item #{n}", quantity: 1})

    prompt = @ctx |> Capsule.build() |> Capsule.to_prompt()
    assert prompt =~ "Pantry has:"
    refute prompt =~ "more"
  end

  test "to_prompt/1 is nil for an empty pantry" do
    capsule = Capsule.build(@ctx)
    assert capsule.names == []
    assert capsule.total == 0
    assert Capsule.to_prompt(capsule) == nil
  end
end

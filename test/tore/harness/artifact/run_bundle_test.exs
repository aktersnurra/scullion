defmodule Tore.Harness.Artifact.RunBundleTest do
  use ExUnit.Case, async: true

  alias Tore.Harness.Artifact
  alias Tore.Harness.Artifact.RunBundle

  test "kind/0 returns the registered string" do
    assert RunBundle.kind() == "RunBundle"
  end

  test "summary/1 returns child count" do
    bundle = %RunBundle{child_stream_ids: ["run-a", "run-b", "run-c"]}
    assert %{counts: %{children: 3}} = Artifact.summary(bundle)
  end

  test "is_rationale_complete/1 is true (no per-child rationale on the bundle itself)" do
    assert Artifact.is_rationale_complete(%RunBundle{child_stream_ids: []})
  end

  test "to_json/from_json round-trip" do
    bundle = %RunBundle{child_stream_ids: ["run-a", "run-b"]}
    encoded = Artifact.to_json(bundle)
    assert encoded["__kind__"] == "RunBundle"
    assert RunBundle.from_json(encoded) == bundle
  end

  test "Registry resolves 'RunBundle' to the module" do
    assert {:ok, RunBundle} = Tore.Harness.Artifact.Registry.lookup("RunBundle")
  end
end

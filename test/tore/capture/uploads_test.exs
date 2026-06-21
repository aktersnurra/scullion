defmodule Tore.Capture.UploadsTest do
  use Tore.DataCase, async: false

  alias Tore.Capture.Uploads
  alias Tore.Household

  setup do
    %{household: Household.get_household!()}
  end

  test "content_hash/1 is sha-256 hex of the bytes" do
    assert Uploads.content_hash("hello") ==
             "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
  end

  test "record/4 returns :ok on first upload and :duplicate on a repeat", %{household: h} do
    hash = Uploads.content_hash(<<1, 2, 3>>)

    assert {:ok, "kr_001"} = Uploads.record(h.id, hash, "kr_001", "receipt")
    assert {:duplicate, "kr_001"} = Uploads.record(h.id, hash, "kr_002", "receipt")
  end

  test "different households can upload the same bytes", %{household: h} do
    {:ok, other} = Household.create_household(%{name: "Other", locale: "en"})
    hash = Uploads.content_hash(<<9, 9, 9>>)

    assert {:ok, _} = Uploads.record(h.id, hash, "kr_010", "receipt")
    assert {:ok, _} = Uploads.record(other.id, hash, "kr_011", "receipt")
  end

  test "already_uploaded?/2 surfaces the original stream_id", %{household: h} do
    hash = Uploads.content_hash(<<5, 5, 5>>)
    Uploads.record(h.id, hash, "kr_020", "shelf")

    assert {:ok, "kr_020"} = Uploads.already_uploaded?(h.id, hash)
    assert :fresh = Uploads.already_uploaded?(h.id, "0" |> String.duplicate(64))
  end
end

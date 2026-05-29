defmodule Tore.StorageMockTest do
  use ExUnit.Case, async: false

  alias Tore.Storage.Mock
  alias Tore.Storage.Buckets

  setup do
    start_supervised!(Mock)
    :ok
  end

  test "put_object stores body and returns url" do
    body = "fake image binary"
    {:ok, url} = Mock.put_object(Buckets.recipes(), "recipes/1/abc.jpg", body)
    assert url == "http://mock-storage/tore-recipes/recipes/1/abc.jpg"
    assert Mock.get(Buckets.recipes(), "recipes/1/abc.jpg") == body
  end

  test "get_object_url returns consistent url" do
    url = Mock.get_object_url(Buckets.recipes(), "recipes/1/abc.jpg")
    assert url == "http://mock-storage/tore-recipes/recipes/1/abc.jpg"
  end

  test "delete_object removes stored entry" do
    Mock.put_object(Buckets.receipts(), "receipts/5/img.jpg", "data")
    assert Mock.get(Buckets.receipts(), "receipts/5/img.jpg") == "data"
    :ok = Mock.delete_object(Buckets.receipts(), "receipts/5/img.jpg")
    assert Mock.get(Buckets.receipts(), "receipts/5/img.jpg") == nil
  end

  test "reset clears all entries" do
    Mock.put_object(Buckets.uploads(), "x/y.jpg", "z")
    Mock.reset()
    assert Mock.get(Buckets.uploads(), "x/y.jpg") == nil
  end
end

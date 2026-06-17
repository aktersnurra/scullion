defmodule Tore.StorageMockTest do
  use ExUnit.Case, async: false

  alias Tore.Storage.Mock
  alias Tore.Storage.Buckets

  setup do
    Mock.reset()
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
    Mock.put_object(Buckets.recipes(), "recipes/5/img.jpg", "data")
    assert Mock.get(Buckets.recipes(), "recipes/5/img.jpg") == "data"
    :ok = Mock.delete_object(Buckets.recipes(), "recipes/5/img.jpg")
    assert Mock.get(Buckets.recipes(), "recipes/5/img.jpg") == nil
  end

  test "reset clears all entries" do
    Mock.put_object(Buckets.recipes(), "x/y.jpg", "z")
    Mock.reset()
    assert Mock.get(Buckets.recipes(), "x/y.jpg") == nil
  end

  test "get_object returns stored body" do
    Mock.put_object(Buckets.recipes(), "recipes/1/abc.jpg", "image bytes")
    assert Mock.get_object(Buckets.recipes(), "recipes/1/abc.jpg") == {:ok, "image bytes"}
  end

  test "get_object returns error for missing key" do
    assert Mock.get_object(Buckets.recipes(), "recipes/1/missing.jpg") == {:error, :not_found}
  end
end

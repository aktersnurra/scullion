defmodule Scullion.Accounts.RateLimiterTest do
  use ExUnit.Case, async: false
  alias Scullion.Accounts.RateLimiter

  # Use unique IPs per test to avoid state bleed between concurrent tests
  defp unique_ip,
    do: "10.0.#{:rand.uniform(255)}.#{:rand.uniform(255)}-#{System.unique_integer()}"

  describe "check/1" do
    test "returns :ok when no failures recorded" do
      assert :ok = RateLimiter.check(unique_ip())
    end

    test "returns :ok after fewer than 5 failures" do
      ip = unique_ip()
      for _ <- 1..4, do: RateLimiter.record_failure(ip)
      assert :ok = RateLimiter.check(ip)
    end

    test "returns locked error after 5 failures" do
      ip = unique_ip()
      for _ <- 1..5, do: RateLimiter.record_failure(ip)
      assert {:error, :locked, retry_after} = RateLimiter.check(ip)
      assert retry_after > 0 and retry_after <= 60
    end
  end

  describe "record_failure/1" do
    test "locks after exactly 5 failures" do
      ip = unique_ip()
      for _ <- 1..4, do: RateLimiter.record_failure(ip)
      assert :ok = RateLimiter.check(ip)
      RateLimiter.record_failure(ip)
      assert {:error, :locked, _} = RateLimiter.check(ip)
    end

    test "lockout duration escalates: 5→60s, 6→120s, 7→300s" do
      ip = unique_ip()
      for _ <- 1..5, do: RateLimiter.record_failure(ip)
      {:error, :locked, t5} = RateLimiter.check(ip)
      assert t5 <= 60

      RateLimiter.record_failure(ip)
      {:error, :locked, t6} = RateLimiter.check(ip)
      assert t6 > 60 and t6 <= 120

      RateLimiter.record_failure(ip)
      {:error, :locked, t7} = RateLimiter.check(ip)
      assert t7 > 120 and t7 <= 300
    end

    test "8+ failures get max lockout of 1800s" do
      ip = unique_ip()
      for _ <- 1..8, do: RateLimiter.record_failure(ip)
      {:error, :locked, retry_after} = RateLimiter.check(ip)
      assert retry_after > 300 and retry_after <= 1800
    end
  end

  describe "record_success/1" do
    test "clears all failures and lock" do
      ip = unique_ip()
      for _ <- 1..5, do: RateLimiter.record_failure(ip)
      assert {:error, :locked, _} = RateLimiter.check(ip)
      RateLimiter.record_success(ip)
      assert :ok = RateLimiter.check(ip)
    end

    test "is a no-op for unknown ip" do
      ip = unique_ip()
      assert :ok = RateLimiter.record_success(ip)
      assert :ok = RateLimiter.check(ip)
    end
  end
end

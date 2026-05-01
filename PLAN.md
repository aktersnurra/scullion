# Phase 2 — Auth & First Boot

## Overview

Implement the full authentication layer: 16-digit account codes, Argon2 hashing, first-boot
admin setup, numpad login LiveView, IP-based rate limiting, session management, device token
auth for kiosk, and role enforcement in the router.

No new aggregates or CRUD contexts — this phase is purely auth infrastructure.

---

## New dependency

```elixir
# mix.exs
{:argon2_elixir, "~> 3.2"}
```

No other new deps. Rate limiting is a small GenServer backed by ETS (no external lib needed).

---

## New migrations (2 files)

### priv/repo/migrations/20260501000002_create_users.exs

```elixir
create table(:users) do
  add :name, :string, null: false
  add :account_code_hash, :string, null: false
  add :role, :string, null: false, default: "member"
  add :preferences, :map, null: false, default: %{}
  timestamps()
end
```

### priv/repo/migrations/20260501000003_create_device_tokens.exs

```elixir
create table(:device_tokens) do
  add :token_hash, :string, null: false
  add :name, :string, null: false
  add :revoked_at, :utc_datetime
  timestamps()
end
create unique_index(:device_tokens, [:token_hash])
```

---

## Files to create (new)

### lib/scullion/accounts/rate_limiter.ex

GenServer backed by ETS. Tracks per-IP failure counts and lockouts.

```
Public API:
  check(ip :: String.t()) :: :ok | {:error, :locked, retry_after_seconds :: non_neg_integer()}
  record_failure(ip :: String.t()) :: :ok
  record_success(ip :: String.t()) :: :ok
```

ETS schema: `{ip, failures :: non_neg_integer(), locked_until :: integer() | nil}`

Lockout schedule (after N total failures):
- 1–4 failures: no lockout, just increment
- 5 failures: lock 60 s
- 6: lock 120 s
- 7: lock 300 s
- 8+: lock 1800 s (30 min)

`check/1`: if `locked_until` is in the future → return `{:error, :locked, seconds_remaining}`.

### lib/scullion_web/live/auth.ex

`on_mount` callback for LiveView auth. Used via `live_session` in router.

```elixir
defmodule ScullionWeb.Live.Auth do
  def on_mount(:require_authenticated, _params, session, socket)
  def on_mount(:require_admin, _params, session, socket)
  # Loads current_user from session[:user_id], halts+redirects if missing/wrong role
end
```

---

## Files to modify

### mix.exs

Add `{:argon2_elixir, "~> 3.2"}` to deps.

### lib/scullion/accounts/user.ex

Add changeset. No virtual field — code is returned separately from `create_admin`.

```elixir
schema "users" do
  field :name, :string
  field :account_code_hash, :string
  field :role, Ecto.Enum, values: [:admin, :member], default: :member
  field :preferences, :map, default: %{}
  timestamps()
end

def changeset(user, attrs)              # validates name, role
def registration_changeset(user, attrs) # sets account_code_hash from pre-hashed value
def preferences_changeset(user, attrs)  # validates preferences map
```

### lib/scullion/accounts/device_token.ex

Add changeset.

```elixir
schema "device_tokens" do
  field :token_hash, :string
  field :name, :string
  field :revoked_at, :utc_datetime
  timestamps()
end

def changeset(token, attrs)   # validates name, token_hash
def revoke_changeset(token)   # sets revoked_at to now
```

### lib/scullion/accounts.ex

Full implementation. Replace all `{:error, :not_implemented}` stubs.

```elixir
# Read API
def setup_complete?() :: boolean          # any admin user exists?
def get_user!(id) :: User.t()
def list_users() :: [User.t()]
def list_device_tokens() :: [DeviceToken.t()]

# Write API
def create_admin(name) :: {:ok, {User.t(), raw_code :: String.t()}} | {:error, Changeset.t()}
def create_user(attrs) :: {:ok, {User.t(), raw_code :: String.t()}} | {:error, Changeset.t()}
def authenticate(code :: String.t()) :: {:ok, User.t()} | {:error, :invalid_code}
def update_preferences(user, attrs) :: {:ok, User.t()} | {:error, Changeset.t()}
def generate_device_token(name) :: {:ok, {DeviceToken.t(), raw_token :: String.t()}} | {:error, Changeset.t()}
def revoke_device_token(token_id) :: :ok | {:error, :not_found}
def verify_device_token(raw_token :: String.t()) :: {:ok, :kiosk} | {:error, :invalid}
```

Key implementation details:

**Code generation** (`generate_code/0`, private):
```elixir
defp generate_code do
  :crypto.strong_rand_bytes(16)
  |> :binary.bin_to_list()
  |> Enum.map(&rem(&1, 10))
  |> Enum.map(&Integer.to_string/1)
  |> Enum.join()
end
```
Slight bias (256 mod 10 = 6; digits 0–5 appear ~0.4% more often) — acceptable for auth codes.

**create_admin/1**: calls `generate_code/0`, hashes with `Argon2.hash_pwd_salt(code)`,
inserts user with role `:admin`. Returns `{user, raw_code}` on success.

**create_user/1**: same as create_admin but role defaults to `:member`.

**authenticate/1**: strips non-digits, loads all users, calls `Argon2.verify_pass(code, user.account_code_hash)` for each. Returns `{:ok, user}` on first match, `{:error, :invalid_code}` if none. With ≤10 users this is fine.

**generate_device_token/1**: generates `Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)` (64-char hex). Hashes with `:crypto.hash(:sha256, token) |> Base.encode64()` (SHA256 appropriate for high-entropy tokens). Returns `{record, raw_token}`.

**verify_device_token/1**: SHA256-hashes the incoming token, queries DB `WHERE token_hash = hash AND revoked_at IS NULL`.

### lib/scullion/application.ex

Add `Scullion.Accounts.RateLimiter` to the supervision tree (before the endpoint).

### lib/scullion_web/plugs/auth.ex

Session-based auth plug. Runs in `:require_auth` pipeline.

```
- Read user_id from session
- Load user with Accounts.get_user!(id), rescue Ecto.NoResultsError → redirect
- Assign conn.assigns.current_user
- If no session: redirect to /login, halt
```

### lib/scullion_web/plugs/device_auth.ex

Device token auth plug. Runs in a `:kiosk` pipeline (future use in Phase 9).

```
- Read "x-device-token" header (or "token" query param as fallback)
- Call Accounts.verify_device_token(raw_token)
- {:ok, :kiosk} → assign conn.assigns.current_user = %{role: :kiosk}
- {:error, _} → send 401, halt
```

### lib/scullion_web/live/setup_live.ex

First-boot admin creation.

State: `%{name: "", code: nil, done: false}`

Flow:
- `mount`: if `Accounts.setup_complete?()`, redirect to `/login`
- Render: simple form — name text input + "Create account" button
- `handle_event("submit", %{"name" => name}, socket)`:
  - Call `Accounts.create_admin(name)`
  - On `{:ok, {_user, code}}`: assign `code`, set `done: true` — display code formatted as `XXXX XXXX XXXX XXXX`
  - On `{:error, _}`: show generic error ("Name is required")
- Once code is shown, setup is locked — any re-mount redirects to `/login`

### lib/scullion_web/live/login_live.ex

Numpad login.

State: `%{digits: [], error: nil, locked: false, retry_after: 0}`

Flow:
- `mount`: if user already authenticated, redirect to `/`; check rate limit for conn IP
- Render: 4-group dot display (`●●●● ●●●● ●●●● ●●●●` filling in as digits added) + numpad (0–9, backspace, submit)
- `handle_event("digit", %{"value" => d}, socket)`: append if `length(digits) < 16`
- `handle_event("backspace", _, socket)`: drop last digit
- `handle_event("submit", _, socket)`:
  - If `length(digits) < 16`: assign `error: "Enter all 16 digits"`
  - Check rate limit; if locked: assign locked state
  - Call `Accounts.authenticate(Enum.join(digits))`
  - On `{:ok, user}`: `RateLimiter.record_success(ip)`, `put_session(socket, :user_id, user.id)`, `push_navigate(socket, to: "/")`
  - On `{:error, :invalid_code}`: `RateLimiter.record_failure(ip)`, re-check limit, assign error

Session write from LiveView: use `put_session(socket, :user_id, user.id)` (available in phoenix_live_view >= 0.20).

### lib/scullion_web/router.ex

Full router with all pipelines and live sessions.

```elixir
pipeline :browser do ... end  # unchanged

pipeline :require_auth do
  plug ScullionWeb.Plugs.Auth
end

# Public — no auth required
scope "/", ScullionWeb do
  pipe_through :browser
  live "/setup", Live.SetupLive
  live "/login", Live.LoginLive
end

# Authenticated users (member + admin)
scope "/", ScullionWeb do
  pipe_through [:browser, :require_auth]
  live_session :authenticated,
    on_mount: [{ScullionWeb.Live.Auth, :require_authenticated}] do
    live "/", Live.PlannerLive
    live "/recipes", Live.RecipeLive
    live "/groceries", Live.GroceryLive
    live "/prep", Live.PrepLive
    live "/deals", Live.DealsLive
    live "/pantry", Live.PantryLive
    live "/costs", Live.CostLive
  end
end

# Admin only
scope "/", ScullionWeb do
  pipe_through [:browser, :require_auth]
  live_session :admin,
    on_mount: [{ScullionWeb.Live.Auth, :require_admin}] do
    live "/settings", Live.SettingsLive
  end
end
```

---

## Test files to modify/create

### test/scullion/accounts_test.exs (replace stub)

```
describe "setup_complete?/0"
describe "create_admin/1"           — creates user, returns 16-digit code, hash stored in DB
describe "create_user/1"
describe "authenticate/1"           — valid code, invalid code, wrong code
describe "generate_device_token/1"  — creates token record, returns 64-char hex
describe "verify_device_token/1"    — valid, revoked, wrong
describe "revoke_device_token/1"
describe "update_preferences/2"
```

### test/scullion/accounts/rate_limiter_test.exs (new)

```
describe "check/1"           — ok when no failures, locked after threshold
describe "record_failure/1"  — increments, triggers lockout at 5
describe "record_success/1"  — resets counter and lock
```

### test/scullion_web/live/setup_live_test.exs (new)

```
test "renders form when no admin exists"
test "redirects to /login when setup already complete"
test "creates admin and shows 16-digit code"
test "code is displayed in XXXX XXXX XXXX XXXX format"
```

### test/scullion_web/live/login_live_test.exs (new)

```
test "renders numpad"
test "accumulates digits up to 16"
test "backspace removes last digit"
test "rejects submission with fewer than 16 digits"
test "authenticates valid code and redirects"
test "rejects invalid code and shows error"
test "shows lock error after 5 failures"
```

---

## Implementation order

1. Add `argon2_elixir` → `mix deps.get`
2. Write migrations 002 + 003 → `mix ecto.migrate`
3. `accounts/rate_limiter.ex`
4. `accounts/user.ex` (add changesets)
5. `accounts/device_token.ex` (add changesets)
6. `accounts.ex` (full implementation)
7. `application.ex` (add RateLimiter to supervision tree)
8. `live/auth.ex` (on_mount callbacks)
9. `plugs/auth.ex` + `plugs/device_auth.ex`
10. `live/setup_live.ex`
11. `live/login_live.ex`
12. `router.ex`
13. Tests
14. `mix compile --warnings-as-errors && mix test`

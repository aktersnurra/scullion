defmodule Scullion.Accounts do
  import Ecto.Query
  alias Scullion.Repo
  alias Scullion.Accounts.{User, DeviceToken}

  @spec setup_complete?() :: boolean()
  def setup_complete? do
    Repo.exists?(from u in User, where: u.role == :admin)
  end

  @spec get_user!(term()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  @spec list_users() :: [User.t()]
  def list_users, do: Repo.all(User)

  @spec list_device_tokens() :: [DeviceToken.t()]
  def list_device_tokens, do: Repo.all(DeviceToken)

  @spec create_admin(String.t()) :: {:ok, {User.t(), String.t()}} | {:error, Ecto.Changeset.t()}
  def create_admin(name), do: create_with_role(name, :admin)

  @spec create_user(map()) :: {:ok, {User.t(), String.t()}} | {:error, Ecto.Changeset.t()}
  def create_user(attrs) when is_map(attrs) do
    name = Map.get(attrs, :name) || Map.get(attrs, "name", "")
    create_with_role(name, :member)
  end

  @spec authenticate(String.t()) :: {:ok, User.t()} | {:error, :invalid_code}
  def authenticate(code) when is_binary(code) do
    normalized = String.replace(code, ~r/\D/, "")

    Repo.all(User)
    |> Enum.find_value({:error, :invalid_code}, fn user ->
      if Argon2.verify_pass(normalized, user.account_code_hash), do: {:ok, user}
    end)
  end

  @spec update_preferences(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_preferences(user, attrs) do
    user
    |> User.preferences_changeset(attrs)
    |> Repo.update()
  end

  @spec generate_device_token(String.t()) ::
          {:ok, {DeviceToken.t(), String.t()}} | {:error, Ecto.Changeset.t()}
  def generate_device_token(name) do
    raw_token = Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
    token_hash = sha256(raw_token)

    %DeviceToken{}
    |> DeviceToken.changeset(%{name: name, token_hash: token_hash})
    |> Repo.insert()
    |> case do
      {:ok, record} -> {:ok, {record, raw_token}}
      {:error, cs} -> {:error, cs}
    end
  end

  @spec revoke_device_token(term()) :: :ok | {:error, :not_found}
  def revoke_device_token(token_id) do
    case Repo.get(DeviceToken, token_id) do
      nil ->
        {:error, :not_found}

      token ->
        token |> DeviceToken.revoke_changeset() |> Repo.update!()
        :ok
    end
  end

  @spec verify_device_token(String.t()) :: {:ok, :kiosk} | {:error, :invalid}
  def verify_device_token(raw_token) when is_binary(raw_token) and raw_token != "" do
    hash = sha256(raw_token)

    case Repo.one(from t in DeviceToken, where: t.token_hash == ^hash and is_nil(t.revoked_at)) do
      nil -> {:error, :invalid}
      _token -> {:ok, :kiosk}
    end
  end

  def verify_device_token(_), do: {:error, :invalid}

  defp create_with_role(name, role) do
    code = generate_code()
    hash = Argon2.hash_pwd_salt(code)

    %User{}
    |> User.registration_changeset(%{name: name, role: role, account_code_hash: hash})
    |> Repo.insert()
    |> case do
      {:ok, user} -> {:ok, {user, code}}
      {:error, cs} -> {:error, cs}
    end
  end

  defp generate_code do
    :crypto.strong_rand_bytes(16)
    |> :binary.bin_to_list()
    |> Enum.map(&rem(&1, 10))
    |> Enum.map(&Integer.to_string/1)
    |> Enum.join()
  end

  defp sha256(value) do
    :crypto.hash(:sha256, value) |> Base.encode64()
  end
end

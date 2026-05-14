defmodule Scullion.Repo.Migrations.AddKeyToIngredients do
  use Ecto.Migration

  @doc """
  Backfills key from name using SQLite string functions. Collisions from dirty
  historical data (e.g. "Salt"/"salt", "Olive Oil"/"olive oil") are resolved by
  appending the row id, producing e.g. "salt_12". This keeps the column non-null
  and unique without losing any rows.
  """
  def up do
    alter table(:ingredients) do
      add :key, :string
    end

    # First pass: set key for all rows
    execute """
    UPDATE ingredients SET key = lower(
      replace(replace(replace(replace(replace(replace(
        replace(replace(replace(replace(replace(replace(replace(
          name,
          'å', 'a'), 'ä', 'a'), 'ö', 'o'),
          'Å', 'a'), 'Ä', 'a'), 'Ö', 'o'),
          ' ', '_'), '-', '_'), '/', '_'), ',', ''), '.', ''), '(', ''), ')', '')
      )
    """

    # Second pass: resolve collisions by appending row id
    execute """
    UPDATE ingredients SET key = key || '_' || id
    WHERE id NOT IN (
      SELECT MIN(id) FROM ingredients GROUP BY key
    )
    """

    create unique_index(:ingredients, [:key])
  end

  def down do
    drop unique_index(:ingredients, [:key])

    alter table(:ingredients) do
      remove :key
    end
  end
end

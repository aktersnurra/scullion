defmodule Tore.Harness.ProjectorSupervisor do
  use DynamicSupervisor
  alias Tore.Harness.{Projector, ProjectorRegistry}

  def start_link(_), do: DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec start_or_lookup(integer()) :: {:ok, pid()}
  def start_or_lookup(household_id) do
    case Registry.lookup(ProjectorRegistry, household_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        spec = %{
          id: {Projector, household_id},
          start: {Projector, :start_link, [household_id]},
          restart: :transient
        }

        case DynamicSupervisor.start_child(__MODULE__, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
        end
    end
  end
end

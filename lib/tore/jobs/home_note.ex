defmodule Tore.Jobs.HomeNote do
  def run do
    Tore.CounterNotes.build_home_note(Date.utc_today())
  end
end

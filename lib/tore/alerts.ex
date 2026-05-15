defmodule Tore.Alerts do
  import Swoosh.Email

  alias Tore.Mailer

  @from {"Tore", "tore@rydholm.dev"}
  @to "gustaf.rydholm@gmail.com"

  def scrape_zero_results(url, chain) do
    new()
    |> to(@to)
    |> from(@from)
    |> subject("[Tore] Scrape returned 0 deals — parser may be broken")
    |> text_body("Chain: #{chain}\nURL: #{url}\n\nCheck the ICA parser — the page structure may have changed.")
    |> Mailer.deliver()
  end
end

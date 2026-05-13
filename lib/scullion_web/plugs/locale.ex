defmodule ScullionWeb.Plugs.Locale do
  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    locale =
      case conn.assigns[:current_user] do
        %{locale: locale} when is_binary(locale) -> locale
        _ -> "sv"
      end

    Gettext.put_locale(ScullionWeb.Gettext, locale)
    conn
  end
end

defmodule PlateSlateWeb.ItemController do
  use PlateSlateWeb, :controller
  use Absinthe.Phoenix.Controller, schema: PlateSlateWeb.Schema

  @graphql """
  query Index @action(mode: INTERNAL) {
    menu_items
  }
  """
  def index(conn, result) do
    render(conn, "index.html", items: result.data.menu_items)
  end
end

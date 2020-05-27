defmodule PlateSlateWeb.Resolvers.Menu do
  alias PlateSlate.Menu

  def menu_items(_, args, _) do
    {:ok, Menu.list_items(args)}
  end

  def search(_, %{matching: term}, _) do
    {:ok, Menu.search(term)}
  end

  def create_item(_, %{input: params}, %{context: _context}) do
    with {:ok, item} <- Menu.create_item(params) do
      {:ok, %{menu_item: item}}
    end
  end
end

defmodule PlateSlateWeb.Resolvers.Menu do
  import Absinthe.Resolution.Helpers, only: [on_load: 2]

  alias PlateSlate.Menu

  def menu_items(_, args, _) do
    {:ok, Menu.list_items(args)}
  end

  def items_for_category(category, _, _) do
    query = Ecto.assoc(category, :items)
    {:ok, PlateSlate.Repo.all(query)}
  end

  def category_for_item(menu_item, _, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(Menu, :category, menu_item)
    |> on_load(fn loader ->
      category = Dataloader.get(loader, Menu, :category, menu_item)
      {:ok, category}
    end)
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

defmodule PlateSlateWeb.Schema.AccountsTypes do
  use Absinthe.Schema.Notation

  object :session do
    field :token, :string
    field :user, :user
  end

  enum :role do
    value :employee
    value :customer
  end

  interface :user do
    field :email, :string
    field :name, :string
    resolve_type fn
      %{role: "employee"}, _ -> :employee
      %{role: "customer"}, _ -> :customer
    end
  end

  object :employee do
    interface :user
    field :email, :string
    field :name, :string
  end

  object :customer do
    interface :user
    field :email, :string
    field :name, :string
    field :orders, list_of(:order) do
      resolve fn customer, _, _ ->
        import Ecto.Query

        orders =
          PlateSlate.Ordering.Order
          |> where(customer_id: ^customer.id)
          |> PlateSlate.Repo.all()

        {:ok, orders}
      end
    end
  end
end

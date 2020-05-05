defmodule PlateSlate.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders) do
      add :customer_number, :integer
      add :items, :map
      add :ordered_at, :utc_datetime, new_valuell: false, default: fragment("now()")
      add :state, :string, null: false, default: "created"

      timestamps()
    end

  end
end

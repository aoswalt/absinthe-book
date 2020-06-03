defmodule PlateSlate.Repo.Migrations.CreateOrderItemView do
  use Ecto.Migration

  def up do
    execute("""
      create view order_items as
        select
            i.*
          , o.id as order_id
        from orders o
           , jsonb_to_recordset(o.items) i(name text, quantity int, price float, id text)
    """)
  end

  def down do
    execute("drop view order_items")
  end
end

# Chapter 4: Adding Flexibility

abstract types like interfaces and unions can make your API simpler (p. 59)

GraphQL fragments to keep their documents shorter and easier to understand (p. 59)

## Organizing a Schema

Absinthe schemas are compiled, meaning that their types are collected, references are resolved, and the overall structure of the schema is verified against a set of rules during Elixir’s module compilation process (p. 59)

GraphQL documents can be processed at runtime using a schema module that’s already been checked for common errors and has been optimized for better performance (p. 59)

### Importing Types

During the module compilation process, all the types referenced in an Absinthe schema are bundled together and built into the compiled module (p. 60)

type modules, because their purpose is to contain a set of types for inclusion in a schema (p. 60)

unlike a schema module, which makes use of `Absinthe.Schema`, type modules use `Absinthe.Schema.Notation` instead. This gives them access to the general type definition macros (like object), without the top-level compilation and verification mechanism that only schemas need (pp. 60-61)

Inside of our schema we use the import_types/1 macro and point it at our new module so that the newly extracted types are still usable from within our schema (p. 61)

```elixir
import_types __MODULE__.MenuTypes
```

During compilation, Absinthe will pull in the type definitions from PlateSlateWeb.Schema.MenuTypes, wiring them into our schema module so they work just like they did when there were defined in-place (p. 61)

The query macro is defined in Absinthe.Schema, and can only be used in our schema module. This is to ensure that we don’t end up with multiple root query object types when importing different type modules (p. 61)

Absinthe’s import_types macro should only be used from your schema module. Think of your schema module like a manifest, defining the complete list of type modules needed to resolve type references (p. 61)

### Importing Fields

To support breaking up a large object, Absinthe provides another macro, import_fields (p. 62)

```elixir
query do
  import_fields :menu_queries
  import_fields :allergen_queries
  import_fields :customer_queries
  import_fields :staff_queries
  import_fields :location_queries

  # Other fields
end
```

Instead of defining the fields directly in the root query object type, we can pull them out and put them into separate types (which we can place in other type modules (p. 62)

```elixir
object :menu_queries do
  field :menu_items, list_of(:menu_item) do
    arg :filter, :menu_item_filter
    arg :order, type: :sort_order, default_value: :asc
    resolve &Resolvers.Menu.list_items/3
  end

  # Other menu-related fields
end
```

It’s just an object type definition, nothing special, and we’d locate it alongside other menu related objects in our menu_types.ex file (p. 63)

Instead of being used as a type for a field’s resolution, however, the `:menu_queries` object type just serves as a convenient named container to hold the fields we’d like to pull into our root query object type (p. 63)

### Deciding on Structure

import_types and import_fields, don’t establish any structural constraints for the way that you arrange your Absinthe-related modules (p. 63)

## Understanding Abstract Types

As-is, distinct search field for every searchable type (p. 64)
```elixir
field :search_categories, list_of(:category) do
  arg :matching, non_null(:string)
  resolve fn _, %{matching: term}, _ ->
    # Search logic
    {:ok , results}
  end
end

field :search_menu_items, list_of(:menu_item) do
  arg :matching, non_null(:string)
  resolve fn _, %{matching: term}, _ ->
    # Similar search logic for a similar field
    {:ok, results}
  end
end
```

model all these search results... as search results (pp. 64-65)
```elixir
field :search, list_of(:search_result) do
  arg :matching, non_null(:string)
  resolve fn _, %{matching: term}, _ ->
    # Combined search logic, returning heterogenous data
    {:ok, results}
  end
end
```

no type-specific fields! Just a single field that users can leverage anytime they want to retrieve records by a search term (p. 65)
```graphql
query Search($term: String!) {
  search(matching: $term) {
    # fields from a mix of search results
  }
}
```

### Using Unions

A GraphQL union type is an abstract type that represents a set of specific concrete types (p. 65)

a `:search_result` could be a union type for both `:menu_item` and `:category` (p. 65)

gropu of `:menu_item` records with a name and description (p. 65)
```elixir
object :category do
  field :name, :string
  field :description, :string
  field :items, list_of(:menu_item) do
    resolve &Resolvers.Menu.items_for_category/3
  end
end
```

load menu items for a category but naive so far (p. 66)
```elixir
def items_for_category(category, _, _) do
  query = Ecto.assoc(category, :items)
  {:ok, PlateSlate.Repo.all(query)}
end
```

this would execute a database query per category (an example of the infamous "N+1" problem (p. 66)

resolver we’ve written where we’re using the first argument, which receives the parent value (p. 66)

In our case this resolver is on the `:items` field of the :category object, so its parent value is a category (p. 66)

define the `:search_result` union type (p. 66)

```elixir
union :search_result do
  types [:menu_item, :category]
  # Almost done...
end
```

The union macro is used to create our type, and works a lot like object (p. 66)

The `types` macro, used inside the union scope, sets its types (p. 66)

Abstract types like unions (and, as you’ll learn about later, interfaces) need a way to determine the concrete type for a value (p. 66)

The resolve_type macro takes a 2-arity function. The first parameter of the function will receive the value that we’re checking, and the second parameter will receive the resolution information (p. 67)

For completeness we provide a fall-through match. It returns nil, which denotes that the value doesn’t belong to any member type of the union (p. 67)

```elixir
union :search_result do
  types [:menu_item, :category]
  resolve_type fn
    %PlateSlate.Menu.Item{}, _ ->
      :menu_item
    %PlateSlate.Menu.Category{}, _ ->
      :category
    _, _ ->
      nil
  end
end
```

search field (p. 67)
```elixir
field :search, list_of(:search_result) do
  arg :matching, non_null(:string)
  resolve &Resolvers.Menu.search/3
end
```

search resolver function. It executes a database query, checking a pattern against names and descriptions for each table, and returns the combined results (p. 67)

Fragments are a way to write chunks of GraphQL that can target a specific type (p. 68)

```graphql
query Search($term: String!) {
  search(matching: $term) {
    ... on MenuItem {
      name
    }
    ... on Category {
      name
      items {
        name
      }
    }
  }
}
```

You can see where we’re defining and inserting fragments on lines 3 and line 6 (p. 68)

The `...` is referred to as a "fragment spread," and inserts the inline fragment that follows (p. 68)

The inline fragment targets a type (introduced with on) and defines the set of fields, within the curly braces, that apply for any item that matches the type (p. 68)

### Introspecting Value Types

Fields that begin with `__` are reserved by GraphQL to support features like [introspection](https://graphql.org/learn/introspection) (p. 70)

The `__typename` introspection field that we’re using here always returns the concrete GraphQL type name that’s in the associated scope (p. 70)

Because unions are about combinations of disparate types that might not have any fields in common, retrieving data from them requires us to use fragments (that target types) to get the data we want (p. 71)

### Using Interfaces

GraphQL interfaces are similar to unions, with one key difference: they add a requirement that any member types must define a set of included fields (p. 71)

```elixir
interface :search_result do
  field :name, :string
  resolve_type fn
    %PlateSlate.Menu.Item{}, _ ->
      :menu_item
    %PlateSlate.Menu.Category{}, _ ->
      :category
    _, _ ->
      nil
  end
end
```

use the `interface` macro instead of the `union` macro, removed the `types` macro usage, only addition we’ve made involves the use of the field macro (p. 72)

```elixir
object :menu_item do
  interfaces [:search_result]
  field :id, :id
  # ...
end
```

an object type can implement as many interfaces as you’d like (p. 73)

the name field is bare, without a wrapping `... on Type { }` inline fragment (p. 74)

selecting fields that have been declared on the interface aren’t subject to the same type of restrictions as selecting fields on unions (p. 74)

If we wanted to retrieve information about menu items that belonged to any categories that were returned from a search, we’d still need to have a wrapping fragment type (p. 74)

because `:items` isn’t declared on the interface. It’s not a field that’s shared with other object types (p. 74)
```graphql
query Search($term: String!) {
  search(matching: $term) {
    name
    ... on Category {
      name
      items {
        name
      }
    }
  }
}
```

If there are fields in common, interfaces allow users to write more simple, readable GraphQL (p. 74)

## Using Named Fragments

Named fragments are just like inline fragments, but they’re reusable (p. 74)

named fragment that’s defined outside the GraphQL operation using the fragment keyword (p. 74)

```graphql
query Search($term: String!) {
  search(matching: $term) {
    ... MenuItemFields
    ... CategoryFields
  }
}

fragment MenuItemFields on MenuItem {
  name
}

fragment CategoryFields on Category {
  name
  items {
    ... MenuItemFields
  }
}
```

Fragments always target a specific type (p. 74)

for menu items that match directly or for menu items that were returned as part of the category, the user would only have to edit the definition for MenuItemFields (p. 75)

Named fragments give users more flexibility to build documents the way they want (p. 75)

Named fragments can include references to other fragments, but can’t form cycles (p. 76)

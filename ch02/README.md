# Chapter 2: Building a Schema

The schema is used by GraphQL servers as the canonical source of information when deciding how to respond to a request. (p. 15)

## Our Schema Module

A GraphQL schema defines its domain model and how data is retrieved. (p. 16)

An example query from a client accessing a list of menu items might look something like this: (p. 17)
```graphql
{
  menuItems {
    name
  }
}
```

If the user was talking to us, this would translate to “Give me the names of all of the menu items that you have.” (p. 17)

Here’s a sample of the type of JSON they’d expect in response: (p. 17)
```json
{
  "data": {
    "menuItems": [
      { "name": "Reuben" },
      { "name": "Croque Monsieur" },
      { "name": "Muffuletta" }
    ]
  }
}
```

To make this happen, we need to define a GraphQL object type for our menu items. (p. 17)

### Defining an Object Type

All data in GraphQL has an associated type. (p. 17)

Our menu item type is what GraphQL refers to as an object, since it contains a number of fields (like name). (p. 17)

Your API and the underlying data representations do not need to be identical, or even have the same structure. One of the main values in modeling GraphQL types is that they can serve as an abstraction. (One example is using the encounters association being used to get the last encounter). (p. 17)

The beginnings of the schema module, with the boilerplate for our new menu item type. You can see we’re also stubbing out the query definition for now (more on that soon): (p. 18)
```elixir
defmodule PlateSlateWeb.Schema do
  use Absinthe.Schema

  query do
    # Ignore for now
  end

  object :menu_item do
    # adding fields soon
  end
end
```

Absinthe models the types that we define as Elixir structs. (pp. 18-19)
* _identifier_ The internal identifier Absinthe uses to refer to this type. As we define the schema, we’ll be using it a lot, too
* _description_ Documentation we can provide for an object type that will be automatically available to API users using GraphQL’s built-in introspection features
* _name_ The canonical GraphQL type name. While required, this will be automatically generated for you if you don’t provide it yourself, based on the Absinthe identifier
* _fields_ The real meat and potatoes of our object types
* _is_type_of_ and _interfaces_ Support GraphQL’s Union and Interface abstract types (ch 4)

### Adding Fields

Adding a field to an object type is as simple as using the field macro. The macro takes an identifier atom, a type reference, an optional keyword list of attributes, and a further optional block for more in-depth configuration. (p. 19)

We’ll start with the basics, and add :id, :name, and :description fields to our :menu_item object: (p. 19)
```elixir
object :menu_item do
  field :id, :id
  field :name, :string
  field :description, :string
end
```

The identifiers that we’ve chosen for the fields will give the fields canonical GraphQL names of "id", "name", and "description". (Like object types, the canonical GraphQL names of fields are automatically generated for us. (p. 19)

The second argument to the field macro here defines the field type. (p. 19)

## Making a Query

A GraphQL query is the way that API users can ask for specific pieces of information. (p. 21)

To support users getting menu items, we need to provide two things: A way for the user to request objects of the type A way for the system to retrieve (or resolve) the associated data. (p. 21)

The key to the first objective is defining a special object type to serve as the entry point for queries on a GraphQL schema. We already defined it when we used the query macro earlier. (p. 21)

The query macro is just like object, but it handles some extra defaults for us that Absinthe expects. (p. 21)

There’s nothing special about the root query object type structurally. Absinthe will use it as the starting point of queries, determining what top-level fields are available. (p. 22)

_list_of_ is a handy Absinthe macro that we can use to indicate that a field returns a list of a specific type's shorthand for %Absinthe.Type.List{of_type: :menu_item}. That’s a little long to type every time you need to return a list. (p. 22)

Absinthe handles translating between these two conventions automatically so that both the client and the server can work using the formats most familiar to them. The functionality is extensible, too; if you want to use a different naming convention in your GraphQL documents, you can. (p. 22)

We have to retrieve the data for the field. GraphQL refers to this as resolution, and it’s done by defining a resolver for our field. (p. 22)

A field’s resolver is the function that runs to retrieve the data needed for a particular field. (p. 22)

_menu_items_ resolver: (p. 23)
```elixir
query do
  field :menu_items, list_of(:menu_item) do
    resolve fn
      _, _, _ -> {:ok , Repo.all(Menu.Item)}
    end
  end
end
```

Because the field doesn’t need any parameters, we’re ignoring the function arguments and just returning an :ok tuple with the list of menu items. That lets Absinthe know that we were able to resolve the field successfully. (p. 23)

You don’t need to define a resolver function for every field. (p. 23)

If a resolver is not defined for a field, Absinthe will attempt to use the equivalent of Map.get/2 to retrieve a value from the parent value in scope, using the identifier for the field. (p. 24)

Resolution starts at the root of a document and works its way deeper, with each field resolver’s return value acting as the parent value for its child fields. (p. 24)

Because the resolver for menuItems (that is, the resolver we defined in our schema for the :menu_items field) returns a list of menu item values—and resolution is done for each item in a list—the parent value for the name field is a menu item value. (p. 24)

something very close to: (p. 24)
```elixir
  for menu_item
```

## Running Our Query with GraphiQL

GraphiQL is "an in-browser IDE for exploring GraphQL". (p. 24)

Includes three versions of GraphiQL: the official interface[10], an advanced version[11], and GraphQL Playground. (p. 24) (explorer is not included)

Setting up two routes: "/api" with the regular Absinthe.Plug, and "/graphiql" with the GraphiQL plug. The former is what API clients would use and what we’ll use in our tests, and then the latter provides the “in-browser” IDE. (p. 25)

Simplified, official GraphiQL interface, set with the interface: :simple option. (p. 25)

GraphiQL helpfully suggested some autocompletions? That’s because when we loaded the page, it automatically sent an introspection query to our GraphQL API, retrieving the metadata it needs about PlateSlateWeb.Schema to support autocompletion and display documentation. (p. 25)

able to specify additional fields in our query without having to modify the schema any further. (p. 26)

"Docs" link that, when clicked, will open up a new sidebar full of API documentation. (p. 26)

we can add a :description value as part of the third argument to the field macro: (pp. 26-27)
```elixir
field :menu_items, list_of(:menu_item), description: "The list of available items on the menu" do
  # Menu item field definition
end
```

another technique we can use to add descriptions, using a module attribute, @desc, just as you would with Elixir’s @doc: (p. 27)
```elixir
@desc "The list of available items on the menu"
field :menu_items, list_of(:menu_item) do
  # Menu item field definition
end
```

the latter approach supports multi-line documentation more cleanly and sets itself off from the working details of our field definitions (p. 27)

## Testing Our Query

just as we would a Phoenix controller, using the PlateSlate.ConnCase helper module (p. 27)

passes the @query module attribute we defined above (making use of Elixir’s handy multi-line """ string literal) as the :query option, which is what Absinthe.Plug expects (p. 28)

response is then checked to make sure that it has an HTTP 200 status code and includes the JSON data that we expect to see (p. 28)

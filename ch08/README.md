# Chapter 8: Securing with Authentication and Authorization

secure portions of the API behind authentication and authorization checks (p. 139)

## Logging In

not only do we need to keep track of who has ordered what, we need to give each customer the ability to view and subscribe to their orders (and no one else’s) (p. 140)

### Authentication

The first step then is being able to identify whether someone is an employee or a customer (p. 140)

```graphql
mutation Login($email: String!, $password: String!) {
  login(role: EMPLOYEE, email: $email, password: $password) {
    token
  }
}
```

return an API token valid for this particular employee if the supplied email address and password are correct (p. 140)

```json
{
  "data": {
    "login": {
      "token": "EMPLOYEE-TOKEN-HERE"
    }
  }
}
```

single users table that will hold the user’s name, email address, and password. We’ll also have a role column to indicate whether they’re an employee, or a customer (p. 140)

simple authentication mechanism here; just role, email, and password (p. 143)

```elixir
def authenticate(role, email, password) do
  user = Repo.get_by(User, role: to_string(role), email: email)

  with %{password: digest} <- user,
       true <- Password.valid?(password, digest) do
    {:ok, user}
  else
    _ ->:error
  end
end
```

### Login API

a `:login` mutation field to the root mutation type (p. 144)

```elixir
mutation do
  field :login, :session do
    arg :email, non_null(:string)
    arg :password, non_null(:string)
    arg :role, non_null(:role)
    resolve &Resolvers.Accounts.login/3
  end
  # Other mutation fields
end
```

returns a `:session` type (p. 144)

```elixir
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
    field :orders, list_of(:order)
  end
end
```

the `:session` object returned from the `:login` mutation, which contains an API token and a user field. This user field is an interface (p. 145)

Both employee and customer objects have email and name fields. However we still want to keep them as separate objects because, as our API grows, there will be fields that only apply to one but not the other (p. 145)

The resolution function for the login field is `Resolvers.Accounts.login/3` (p. 145)

```elixir
def login(_, %{email: email, password: password, role: role}, _) do
  case Accounts.authenticate(role, email, password) do
    {:ok, user} ->
      token = PlateSlateWeb.Authentication.sign(%{
        role: role,
        id: user.id
      })
      {:ok, %{token: token, user: user}}

    _ ->
      {:error, "incorrect email or password"}
  end
end
```

This module is really just a small wrapper about the token generation abilities we get from `Phoenix.Token` (p. 146)

```elixir
defmodule PlateSlateWeb.Authentication do
  @user_salt "user salt"

  def sign(data) do
    Phoenix.Token.sign(PlateSlateWeb.Endpoint, @user_salt, data)
  end

  def verify(token) do
    Phoenix.Token.verify(PlateSlateWeb.Endpoint, @user_salt, token, [
      max_age: 365 * 24 * 3600
    ])
  end
end
```

The token encodes information about the type of session, as well as who the session belongs to by including the `employee.id`. We’ll need this information to know what role (customers or employees) to use when we want to later look up the user record (p. 146)

small helper module for generating users (p. 146)

```elixir
defmodule Factory do

  def create_user(role) do
    int = :erlang.unique_integer([:positive, :monotonic ])
    params = %{
      name: "Person #{int}",
      email: "fake-#{int}@foo.com",
      password: "super-secret",
      role: role
    }

    %PlateSlate.Accounts.User{}
    |> PlateSlate.Accounts.User.changeset(params)
    |> PlateSlate.Repo.insert!
  end
end
```

We use the employee’s information in our test to ensure that, given the correct credentials, the correct token is returned from our `:login` mutation (p. 147)

Get back an auth token and some information about the employee we just authenticated (p. 147)

```graphql
mutation {
  login(role: CUSTOMER, email: "fake@bar.com", password: "abc123") {
    token
    user { name __typename }
  }
}
```

## Using the Execution Context

The Absinthe feature that addresses this problem is called the execution context. It’s a place where we can set values that will be available to all of our resolvers (like Plug's assigns) (p. 148)

the final argument passed to the resolver function is an `Absinthe.Resolution` struct which includes the context (p. 148)

a basic example of using a context, and how the context is provided to Absinthe (pp. 148-149)

```elixir
defmodule ContextExample.Schema do
  use Absinthe.Schema

  query do
    field :greeting, :string do
      resolve fn _, _, %{context: context} ->
        {:ok, "Welcome #{context.current_user.name}"}
      end
    end
  end
end

# Our document
doc = "{ greeting }"

# Our context
context = %{current_user: %{name: "Alicia"}}

# Running Absinthe manually
Absinthe.run(doc, ContextExample.Schema, context: context)

# Gives this result
{:ok, %{data: %{ "greeting" => "Welcome Alicia" }}}
```

The context that you passed into the `Absinthe.run/3` call is the same context you accessed in the third argument to the resolution function of the greeting field (p. 149)

Whatever we pass into the context is always made available as is in the resolution functions. Importantly, the context is always available in every field at every level and it’s this property that gives it it’s name: it’s the "context" in which execution is happening (more flexible than `Plug.Conn`, which is only available at the controller) (p. 149)

Our application code, however, does not explicitly call `Absinthe.run/3` but instead uses `Absinthe.Plug`, which executes the GraphQL documents that we receive over HTTP. We need to make sure that the context is set-up ahead of time so that it has what it needs to execute documents (p. 149)

### Storing Auth Info in Context with a Plug

`Absinthe.Plug` knows how to extract certain values from the connection automatically for use in the context. All we need to do is write a plug that inserts the appropriate values into the connection first (p. 150)

the `PlateSlateWeb.Context` plug so that it will run prior to `Absinthe.Plug` and give us a place to set up our context (p. 150)

```elixir
pipeline :api do
  plug :accepts, ["json"]
  plug PlateSlateWeb.Context
end
```

```elixir
defmodule PlateSlateWeb.Context do
  @behaviour Plug

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _) do
    context = build_context(conn)
    IO.inspect [context: context]
    Absinthe.Plug.put_options(conn, context: context)
  end

  defp build_context(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, data} <- PlateSlateWeb.Authentication.verify(token),
         %{} = user <- get_user(data) do
      %{current_user: user}
    else
      _ -> %{}
    end
  end

  defp get_user(%{id: id, role: role}) do
    PlateSlate.Accounts.lookup(role, id)
  end
end
```

We use the `call/2` function to return another `%Plug.Conn{}` struct, with our current user helpfully placed behind a context key in the private absinthe namespace. It turns out that this namespace is exactly where `Absinthe.Plug` looks for a pre-built context (p. 151)

looking up the header to get the Phoenix token sent with the request, and then using that token to find the related user (whether they’re a customer or employee) (p. 151)

no `"authorization"` header or if there is no user for a given API key, with will simply fall through to its else clause, where we return the context without a `:current_user` specified (p. 151)

`Accounts.lookup/2` is just a little helper function (p. 151)

```elixir
def lookup(role, id) do
  Repo.get_by(User, role: to_string(role), id: id)
end
```

With the context placed in the connection, `Absinthe.Plug` is properly set up to pass this value along when it runs the document, and it will be available to our resolvers (p. 151)

GraphiQL interface we’ve been using to configure headers (p. 151)

## Securing Fields

to enforce authorization on particular fields: we can just check the context (p. 153)

Having the current user also give us the ability to retrieve associated records in our resolvers, returning information specific to the user (p. 153)

### Inline Authorization

securing the `:create_menu_item` resolver (pp. 153-154)

```elixir
def create_item(_, %{input: params}, %{context: context}) do
  case context do
    %{current_user: %{role: "employee"}} ->
      with {:ok, item} <- Menu.create_item(params) do
        {:ok, %{menu_item: item}}
      end
    _ ->
      {:error, "unauthorized"}
  end
end
```

### Authorization Middleware

Different fields each have slightly different authorization conditions, so we’re going to use the `middleware/2` macro to annotate them individually (p. 156)

```elixir
field :create_menu_item, :menu_item_result do
  arg :input, non_null(:menu_item_input)
  middleware Middleware.Authorize, "employee"
  resolve &Resolvers.Menu.create_item/3
end
```

the resolver, we can just go back to how it was before we had the authorization check (p. 156)

```elixir
def create_item(_, %{ input: params}, _) do
  with {:ok, item} <- Menu.create_item(params) do
    {:ok, %{menu_item: item}}
  end
end
```

check the type of the `current_user` in the resolution function, or handle the possibility that there is no current_user at all. The middleware will handle all of this for us (pp. 156-157)

```elixir
defmodule PlateSlateWeb.Schema.Middleware.Authorize do
  @behaviour Absinthe.Middleware

  def call(resolution, role) do
    with %{current_user: current_user} <- resolution.context,
         true <- correct_role?(current_user, role) do
      resolution
    else
      _ ->
        resolution
        |> Absinthe.Resolution.put_result({:error, "unauthorized"})
    end
  end

  defp correct_role?(%{}, :any), do: true
  defp correct_role?(%{role: role}, role), do: true
  defp correct_role?(_, _), do: false
end
```

The `call/2` function also takes a second argument, which is whatever additional value was supplied to the `middleware/2` call in our schema (p. 157)

if there are any errors on the resolution struct, the `Absinthe.Resolution` middleware will not call our resolve function (p. 157)

only want to allow an order to be placed by a logged in customer or employee (p. 157)

```elixir
field :place_order, :order_result do
  arg :input, non_null(:place_order_input)
  middleware Middleware.Authorize, :any
  resolve &Resolvers.Ordering.place_order/3
end
```

To configure the params though we’ll need to head over to the `place_order/3` resolver function, and conditionally add a value to the place_order_input if the current user is a customer (p. 158)

```elixir
place_order_input = case context[:current_user]
do
  %{role: "customer", id:id} ->
    Map.put(place_order_input, :customer_id, id)
  _ ->
    place_order_input
end
```

Unlike HTTP requests a Phoenix channel connection is stateful. If a GraphQL document makes a change to the context, this will affect other subsequent documents that are executed by that client (p. 159)

modify our login mutation to persist a change to the context with an example of some inline middleware (p. 159)

```elixir
field :login, :session do
  arg :email, non_null(:string)
  arg :password, non_null(:string)
  arg :role, non_null(:role)
  resolve &Resolvers.Accounts.login/3
  middleware fn
    res, _ ->
      with %{value: %{user: user}}
```

### Authorizing Subscriptions

scope `new_order` so that when a subscription is created by a customer, we only route that customer’s orders to that subscription but allow employees to watch for everything (pp. 160,162)

```elixir
subscription do
  # Other fields
  field :new_order, :order do
    config fn _args, %{context: context} ->
      case context[:current_user] do
        %{role: "customer", id: id} -> {:ok, topic: id}
        %{role: "employee"} -> {:ok, topic: "*"}
        _ -> {:error, "unauthorized"}
      end
    end
  end
end
```

At the heart of our solution is the ability to retrieve the current user from within the config function. If the current user is a customer, we’re going to use the customer id as the topic. Employeees still get the `"*"` topic, and everyone else gets an unauthorized message (p. 162)

need to update how we publish orders if we’re to make the id topic useful. This happens back in the `place_order` resolver (p. 162)

```elixir
Absinthe.Subscription.publish(PlateSlateWeb.Endpoint, order, new_order: [order.customer_id, "*"])
```

When we publish an order we’re now publishing on two topics: `"*"` and the id of the customer that ordered it (p. 162)

Subscriptions and authorization is all about topic design. Topics are extremely cheap and should be used readily to help scope published data to precisely the clients that should be able to see it (p. 162)

## Structuring For Authorization

Some authorization concerns can be handled by the very structure of the data within our application (p. 162)

After all, a GraphQL document is a tree; if we can have a single field act as a gatekeeper for any data that requires authorization, it could simplify our code and the amount of mental overhead involved in trying to remember what’s public and what isn’t (p. 163)

orders that are associated with a particular customer record (p. 163)

```graphql
{
  orders {
    id
    items { name quantity}
  }
  menuItems {
    name
  }
}
```

The `menuItems` field always shows the same thing no matter who is looking at that field, and the `orders` field always shows different things depending on who is looking at the field, but there’s nothing in the document that might hint that this is what will happen (p. 163)

The `me` pattern is an approach where fields that always depend on whoever is viewing the API are placed on some object representing the current user so that the document’s structural hierarchy makes that dependency clear (p. 163)

```graphql
{
  me {
    orders {
      id
      items { name quantity }
    }
  }
  menuItems {
    name
  }
}
```

The `menuItems` field still happens at the top level because its values are the same regardless of the current user, whereas the orders field has been placed under me. The shape of the document itself helps communicate what’s going on (p. 164)

This pattern has its roots in the Relay v1 implementation - the original GraphQL framework, now called "Relay Classic" - where the field was called `viewer`. It served to provide both authorization and an easy way to ensure that certain data is always loaded in the context of the current user. We’re using the field name `me`, which is the general convention within the broader GraphQL community at this point (p. 164)

The `:user` interface type we created in the AccountTypes module already encapsulates the possibilities of a "current user" in our system, so we can just go ahead and add the requisite field to our schema (p. 164)

```elixir
query do
  field :me, :user do
    middleware Middleware.Authorize, :any
    resolve &Resolvers.Accounts.me/3
  end
  # Other query fields
end
```

grab the current user out of the context and return it (p. 164)

```elixir
def me(_, _, %{context: %{current_user: current_user}}) do
  {:ok, current_user}
end

def me(_, _, _) do
  {:ok, nil}
end
```

filling out the orders field on the `:customer` object (pp. 164-165)

```elixir
field :orders, list_of(:order) do
  resolve fn customer, _, _ ->
    import Ecto.Query

    orders =
      PlateSlate.Ordering.Order
      |> where(customer_id: ^customer.id)
      |> PlateSlate.Repo.all

    {:ok, orders}
  end
end
```

end up with is a GraphQL query that looks like this (p. 165)

```graphql
{
  me {
    name
    ... on Customer { orders { id } }
  }
  menuItems { name }
}
```

This tell us a lot. We know that the customer has a name, we know that customers have orders, and that those orders are going to be specific to that customer and not include somebody else’s. We also can reasonably expect that the menu items are global values, and won’t be different if our friend checks it (p. 165)

In situations where "authorization" boils down to scoping data under other data, it’s often best to express that scope via the GraphQL document itself (p. 165)

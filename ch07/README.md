# Chapter 7: Resolution Middleware

Absinthe middleware, a tool you can use to make resolvers shorter and more elegant by being able to reuse logic (p. 123)

## Our First Module

several resolution functions that all copied an error handling function (p. 123)

The output of the resolver is a `:menu_item_result` type, which we’ve defined as part of our schema, and includes an `:errors` field (p. 124)

Our resolver builds the error portion of the result using a transform_errors/1 function that turns `%Ecto.Changeset{}` structs into `:input_error` objects (p. 124)

when we added more resolvers to power the ordering system, we just copied and pasted the same code into that resolver too (p. 124)

One option for cleaning this up is to just extract `transform_errors/1` function into its own module, which we could import into both resolvers (p. 124)

functions within our `Menu` and `Ordering` contexts end up returning `{:error, %Ecto.Changeset{}}` when validations fail, and Absinthe doesn’t really know what to do with a changeset (pp. 124-125)

the resolve macro (p. 125)
```elixir
defmacro resolve(function_ast) do
  quote do
    middleware Absinthe.Resolution, unquote (function_ast)
  end
end
```

```elixir
resolve &Resolvers.Menu.menu_items/3
```

expands to

```elixir
  middleware Absinthe.Resolution, &Resolvers.Menu.menu_items/3
```

This `Absinthe.Resolution` middleware has been the driving force behind how our resolvers have operated this whole time, building the arguments to our resolvers, calling them, and then interpreting the result we’ve returned (similar to Plug pipeline) (p. 125)

we know more about our application than Absinthe does, and so by building our own middleware we can inform Absinthe about how to handle data that is more suited to our specific needs (p. 125)

start by ripping the error transformation logic out our resolver modules and putting it inside a new module that will serve as the base of our middleware (p. 125)

the `Absinthe.Middleware` behaviour. Modules that implement this behaviour are required to define a call/2 function that takes an %Absinthe.Resolution{} struct as well as some optional configuration (p. 126)

The resolution struct is packed with information about the field that’s being resolved, including the results or errors that have been returned (p. 126)

The `%Absinthe.Resolution{}` struct plays a role similar to the `%Plug.Conn{}` struct. Each gets passed through a sequence of functions that can transform it for some purpose, and return it at the end (p. 126)

look inside the resolution struct to see if we have a changeset error and, if we do, turn it into the structured error data we’ve been using (p. 126)

```elixir
def call(res, _) do
  # to be completed
  with %{errors: [%Ecto.Changeset{} = changeset]} <- res do
    %{res |
      value: %{errors: transform_errors(changeset)},
      errors: []
    }
  end
end
```

two of the most significant keys inside resolution structs: `:value` and `:errors`. The :value key holds the value that will ultimately get returned for the field, and is used as the parent for any subsequent child fields. The `:errors` key is ultimately combined with errors from every other field and used to populate the top level errors in a GraphQL result (p. 126)

When you return `{:ok, value}` from within a resolver function, the value is placed under the `:value` key of the `%Absinthe.Resolution{}` struct. If you return `{:error, error}`, the error value is added to a list under the `:errors` key of the resolution struct (pp. 126-127)

We use the with macro to check for any changeset errors that would have been put there by a resolver returning `{:error, changeset}`. If we find one, we set the `:value` key to a map holding the transformed errors. We also clear out the `:errors` key, because we don’t want any of this to bubble up to the top level (p. 127)

## Applying Middleware

Sometimes you have middleware that you want to apply to very specific fields, or even just one field (p. 127)

Other times you want to ensure that a particular middleware is always applied to every field in a certain object, or every field that has a particular name and return type (p. 127)

### Macro Approach

When we have specific fields on which we want to place middleware, you’ll want reach for the `middleware/2` macro (p. 127)

All we’ve been doing with resolve is placing a single piece of middleware on our field, `Absinthe.Resolution`, and giving it the function we want to execute (p. 127)

place our newly minted `ChangesetErrors` middleware on the `:create_menu_item` field (pp. 127-128)

```elixir
field :create_menu_item, :menu_item_result do
  # ...
  resolve &Resolvers.Menu.create_item/3
  middleware Middleware.ChangesetErrors
end
```

Notice how we’ve placed it after the `resolve/1` call. When it comes time to execute the `:create_menu_item` field Absinthe goes through each piece of middleware in order. We want our `ChangesetErrors` code to process errors that happen during resolution, so we need to place it after the resolve call (p. 128)

You can have as many `middleware/1,2` calls on a field as you like (p. 128)

In addition to the module based calls you’ve seen, you can also do inline functions, refer to specific remote functions, or even refer to local functions (p. 128)

You can also provide a configuration value that will be passed as the second argument during all middleware `call/2` invocations (p. 128)

With this logic extracted into middleware now, we can drastically simplify our `:create_menu_item` resolver: (p. 128)

```elixir
def create_item(_, %{input: params}, _) do
  with {:ok, item} <- Menu.create_item(params) do
    {:ok, %{menu_item: item}}
  end
end
```

No longer do we need to worry about the error case at all (p. 128)

While Plug was definitely an inspiration for this API, there is at least one major difference: All Absinthe middleware is always run (p. 129)

controller actions will frequently send a result to the client, which halts the connection (p. 129)

### Callback Approach

a schema wide rule that says something to the effect of "all fields on the mutation object should run this middleware after resolution" (p. 130)

```elixir
def middleware(middleware, _field, _object) do
  middleware
end
```

When you `use Absinthe.Schema` in your schema module, it injects a `middleware/3` function that looks just like the one above, which we can override if we want to do some dynamic logic (p. 130)

This function is called for every field in the schema, passing the list of middleware already configured for the field - set using the `resolve/1` macro or a `middleware/1,2` macro call elsewhere in the schema - as well as the actual field and object structs themselves (p. 130)

The `middleware/3` callback is run on every field for an object whenever that object is loaded from the schema (p. 130)

In the current version of Absinthe there is some in memory caching that happens on loaded schema objects. If you run the same query twice, it’s just going to re-use the in memory cache for the second run, so no loading happens (p. 131)

apply error handling middleware on the mutation object, but not elsewhere (p. 131)

```elixir
def middleware(middleware, _field, %{identifier: :mutation}) do
  middleware ++ [Middleware.ChangesetErrors]
end

def middleware(middleware, _field, _object) do
  middleware
end
```

In the `:mutation` clause we’re taking whatever existing middleware is already specified on the field like a resolver, and we’re appending our `ChangesetErrors` module to the end (p. 131)

Much like when we had a sequence of `middleware/1,2` calls in our schema earlier in the chapter, the middleware placed in this list are executed in order (p. 131)

can also significantly improve the ordering resolver as well now (p. 132)

```elixir
def ready_order(_, %{id: id}, _) do
  order = Ordering.get_order!(id)
  with {:ok , order} <- Ordering.update_order(order, %{state: "ready"}) do
    {:ok, %{order: order}}
  end
end
```

## Setting Defaults

Any time a `def middleware` callback returns an empty list of middleware for a field, Absinthe adds the incredibly simple middleware spec `[{Absinthe.Middleware.MapGet, field.identifier}]` (p. 133)

```elixir
def call(%{source: source} = resolution, key) do
  %{resolution | state: :resolved, value: Map.get(source, key)}
end
```

Add allergy info field and object
```elixir
field :allergy_info, list_of(:allergy_info)

object :allergy_info do
  field :allergen, :string
  field :severity, :string
end
```

Our `:allergen` field, for example, is going to do a `Map.get(parent, :allergen)` call on the map inside the JSONB column, but of course there isn’t any such key there. `:allergen` is an atom, but all the keys in that map are strings (p. 136)

can make this work by doing (p. 136)

```elixir
object :allergy_info do
  field :allergen, :string do
    resolve fn parent, _, _ ->
      {:ok, Map.get(parent, "allergen")}
    end
  end

  field :severity, :string do
    resolve fn parent, _, _ ->
      {:ok, Map.get(parent, "severity")}
    end
  end
end
```

could change the default resolver for fields on this object instead (p. 136)

```elixir
def middleware(middleware, field, %{identifier: :allergy_info} = object) do
   new_middleware = {Absinthe.Middleware.MapGet, to_string(field.identifier)}
   middleware
   |> Absinthe.Schema.replace_default(new_middleware, field, object)
end

def middleware(middleware, _field, %{identifier: :mutation}) do
  middleware ++ [Middleware.ChangesetErrors]
end

def middleware(middleware, _field, _object) do
  middleware
end
```

an additional function head for `middleware/3` that pattern matches for fields where the object definition’s identifier matches `:allergy_info` (p. 136)

This new code sets up a new specification using the `Absinthe.Middleware.MapGet` middleware, and passes as its option a stringified version of our field identifier. The middleware will then use the string identifier (instead of an atom) to retrieve the correct value from the map (p. 136)

the `Absinthe.Schema.replace_default/4` function, which handles swapping it in for the existing default in the list (p. 136)

We could just return `[{Absinthe.Middleware.MapGet, to_string(field.identifier)}]` from the function and be done with it, but the `replace_default/4` function is more future-proof. Absinthe itself which may decide to change its default somewhere down the line (p. 137)

# EdgeDBEcto - helper to simplify work with EdgeDB and Ecto

**NOTE**: This project is not an EdgeDB adapter for Ecto.

**WARNING**: It is very likely that this project will be archived after the implementation of the [`*.edgeql RFC`](https://github.com/edgedb/edgedb/discussions/4244) in the Elixir client itself. Use this project at your own risk.

This project makes working with EdgeDB in Elixir a little easier by providing a mapper for data from EdgeDB to Ecto schemas.

It also provides a module to generate functions for all your EdgeQL queries stored in your application's `priv/edgeql/` folder, and support (though quite limited) for `Ecto.Multi`.

`EdgeDBEcto.Queries` will read your EdgeQL queries from `priv/edgeql/<domain>/<query_name>.edgeql` and generate a `<root_module_name>.<domain_module_name>.<query_function_name>/2` function for each query.

Example usage:

`dbschema/default.esdl`:

```edgeql
module default {
    type User {
        property name -> str
        multi link friends -> User;
    }
}
```

---

`priv/edgeql/accounts/get_user_by_id.esdl`:

```edgeql
# edgedb = :query_single!
# mapper = MyApp.Accounts.User

select User {
  id,
  name,
  friends: {
    id,
    name,
  },
}
filter .id = <uuid>$id
```

`edgedb` directive will be used to determine which function the client should use for the query. It must be in atom form.

`mapper` directive will define an Ecto schema to map the result from the EdgeDB client to an Ecto schema.

---

`lib/my_app/accounts/user.ex`:

```elixir
defmodule MyApp.Accounts.User do
    use Ecto.Schema
    use EdgeDBEcto.Mapper

    @type t() :: %__MODULE__{
        id: binary(),
        name: String.t() | nil,
        friends: list(t()) | Ecto.Association.NotLoaded.t()
    }

    # we need custom config for :id because in EdgeDB its UUID
    @primary_key {:id, :binary_id, autogenerate: false}

    schema "default::User" do
        field :name, :string

        has_many :friends, User
    end
end
```

---

`lib/my_app/edgedb.ex`:

```elixir
defmodule MyApp.EdgeDB do
    use EdgeDBEcto,
        name: __MODULE__,
        queries: true,
        otp_app: :my_app
end
```

`:name` will be used in query functions as an implicit name for the EdgeDB client. You can manually pass it or a separate connection from the client to the query function via the `:conn` option.

`:queries` when set to `true` will autogenerate the query function from EdgeQL queries located in the `priv/edgeql/<domain>` directory of the application.

`:otp_app` is the name of the application in which `EdgeDBEcto` will search for queries. Required if `:queries` is set to `true`.

---

`lib/my_app/accounts.ex`:

```elixir
defmodule MyApp.Accounts do
    alias MyApp.Accounts.User

    @spec get_user(binary()) :: User.t()
    def get_user(id) do
        MyApp.EdgeDB.Accounts.get_user(id: id)
    end
end
```

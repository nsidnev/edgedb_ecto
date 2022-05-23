# EdgeDBEcto - helper to simplify work with EdgeDB and Ecto

NOTE: This is not currently an EdgeDB adapter for Ecto. It may become one in the future.

This package makes working with EdgeDB in Elixir a little easier by providing a mapper for data from EdgeDB to Ecto schemas.
It also provides a module to generate functions for all your EdgeQL queries stored in your application's `priv/edgeql/` folder, and support (though quite limited) for `Ecto.Multi`.
`EdgeDBEcto.Queries` will read your EdgeQL queries from `priv/edgeql/<domain>/<query_name>.edgeql` and generate a `<root_module_name>.<domain_module_name>.<query_function_name>/2` function for each query.

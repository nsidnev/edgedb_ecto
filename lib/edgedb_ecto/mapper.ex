defmodule EdgeDBEcto.Mapper do
  defmacro __using__(_opts \\ []) do
    quote location: :keep do
      defimpl EdgeDBEcto.Convertable, for: __MODULE__ do
        def convert(schema, {:ok, value}) do
          convert(schema, value)
        end

        def convert(_schema, {:error, _reason} = error) do
          error
        end

        def convert(_schema, nil) do
          {:ok, nil}
        end

        def convert(schema, %EdgeDB.Set{} = set) do
          result =
            Enum.reduce_while(set, {:ok, []}, fn item, {:ok, acc} ->
              case convert(schema, item) do
                {:ok, result} ->
                  {:cont, {:ok, [result | acc]}}

                {:error, _reason} = error ->
                  {:halt, error}
              end
            end)

          case result do
            {:ok, schemas} ->
              {:ok, Enum.reverse(schemas)}

            {:error, _reason} = error ->
              error
          end
        end

        def convert(%{__struct__: schema_mod} = schema, %EdgeDB.Object{} = object) do
          with {:ok, associtations} <- convert_links(schema, object),
               {:ok, fields} <- convert_properties(schema, object) do
            build_schema(schema, fields, associtations)
          end
        end

        defdelegate convert!(type, value), to: EdgeDBEcto.Convertable.Any

        defp convert_links(%{__struct__: schema_mod}, object) do
          schema_associations = schema_mod.__schema__(:associations)

          Enum.reduce_while(schema_associations, {:ok, %{}}, fn link_name, {:ok, associations} ->
            link = object[link_name]
            association_meta = schema_mod.__schema__(:association, link_name)

            case EdgeDBEcto.Convertable.convert(association_meta.related, link) do
              {:ok, nil} ->
                {:cont, {:ok, associations}}

              {:ok, []} ->
                {:cont, {:ok, associations}}

              {:ok, association} ->
                {:cont, {:ok, Map.put(associations, link_name, association)}}

              {:error, _reason} = error ->
                {:halt, error}
            end
          end)
        end

        defp convert_properties(%{__struct__: schema_mod}, object) do
          schema_fields = schema_mod.__schema__(:fields)
          associations_meta = schema_mod.__schema__(:associations)

          associations_fields =
            associations_meta
            |> Enum.map(&schema_mod.__schema__(:association, &1))
            |> Enum.map(fn
              %Ecto.Association.Has{related_key: related_key} ->
                related_key

              assocation ->
                assocation.owner_key
            end)

          schema_fields
          |> Enum.reject(&(&1 in associations_fields))
          |> Enum.reduce_while({:ok, %{}}, fn property_name, {:ok, fields} ->
            property = object[property_name]
            type = schema_mod.__schema__(:type, property_name)

            case EdgeDBEcto.Convertable.convert(type, property) do
              {:ok, value} ->
                {:cont, {:ok, Map.put(fields, property_name, value)}}

              {:error, _reason} = error ->
                {:halt, error}
            end
          end)
        end

        defp build_schema(schema, fields, associations) do
          changeset = Ecto.Changeset.change(schema)

          fields
          |> Enum.reduce(changeset, fn {name, value}, changeset ->
            Ecto.Changeset.put_change(changeset, name, value)
          end)
          |> then(fn changeset ->
            Enum.reduce(associations, changeset, fn {name, associations}, changeset ->
              Ecto.Changeset.put_assoc(changeset, name, associations)
            end)
          end)
          |> Ecto.Changeset.apply_action(:edgedb_convert)
        end
      end
    end
  end
end

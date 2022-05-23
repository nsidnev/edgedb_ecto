defprotocol EdgeDBEcto.Convertable do
  # protocol for converting data from EdgeDB driver to Ecto form

  @spec convert(term(), term()) :: {:ok, term()} | {:error, term()} | :error
  def convert(type, value)

  @spec convert(term(), term()) :: term()
  def convert!(type, value)
end

defimpl EdgeDBEcto.Convertable, for: Atom do
  @ecto_primitives ~w(
    integer
    float
    decimal
    boolean
    string
    map
    binary
    id
    binary_id
    utc_datetime
    naive_datetime
    date
    time
    utc_datetime_usec
    naive_datetime_usec
    time_usec
  )a

  @ecto_collections ~w(
    map
  )a

  def convert(type, {:ok, value}) do
    convert(type, value)
  end

  def convert(_type, {:error, _reason} = error) do
    error
  end

  def convert(nil, value) do
    {:ok, value}
  end

  def convert(:any, value) do
    Ecto.Type.cast(:any, value)
  end

  # if set is empty, then it's nil
  # else it's an error
  def convert(type, %EdgeDB.Set{} = set) when type in @ecto_primitives do
    if EdgeDB.Set.empty?(set) do
      Ecto.Type.cast(type, nil)
    else
      {:error, :unexpected_set_for_scalar}
    end
  end

  def convert(type, value) when type in @ecto_primitives do
    Ecto.Type.cast(type, value)
  end

  def convert(type, %EdgeDB.Set{} = set) when type in @ecto_collections do
    value = Enum.to_list(set)
    Ecto.Type.cast(type, value)
  end

  def convert(type, value) when type in @ecto_collections do
    Ecto.Type.cast(type, value)
  end

  # module or custom Ecto type
  def convert(type, value) do
    EdgeDBEcto.Convertable.convert(struct(type), value)
  rescue
    UndefinedFunctionError ->
      Ecto.Type.cast(type, value)
  end

  defdelegate convert!(type, value), to: EdgeDBEcto.Convertable.Any
end

# support for Ecto.ParameterizedType, parametrized collections
defimpl EdgeDBEcto.Convertable, for: Tuple do
  def convert(type, {:ok, value}) do
    convert(type, value)
  end

  def convert(_type, {:error, _reason} = error) do
    error
  end

  # if it's parametrized type then convert set into list and pass as is
  # maybe type handles that
  def convert({:parameterized, _type, _opts} = type, %EdgeDB.Set{} = set) do
    value = Enum.to_list(set)
    convert(type, value)
  end

  def convert(type, %EdgeDB.Set{} = set) do
    value = Enum.to_list(set)
    convert(type, value)
  end

  def convert(type, value) do
    Ecto.Type.cast(type, value)
  end

  defdelegate convert!(type, value), to: EdgeDBEcto.Convertable.Any
end

# default implementation is just return passed data as is
defimpl EdgeDBEcto.Convertable, for: Any do
  def convert(_type, {:ok, value}) do
    {:ok, value}
  end

  def convert(_type, {:error, _reason} = error) do
    error
  end

  def convert(_type, value) do
    {:ok, value}
  end

  def convert!(type, value) do
    case EdgeDBEcto.Convertable.convert(type, value) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise RuntimeError,
              "unable to convert #{inspect(value)} for type #{inspect(type)} from EdgeDB: #{inspect(reason)}"
    end
  end
end

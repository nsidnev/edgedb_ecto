defmodule EdgeDBEcto.Queries do
  @directive_regex ~r/^\s*#\s*(?<directive>.*)\s*\=\s*(?<value>.*)\s*$/

  defmacro __using__(opts \\ []) do
    {opts, _bindings} = Code.eval_quoted(opts, [], __CALLER__)
    otp_app = Keyword.fetch!(opts, :otp_app)
    edgedb_name = Keyword.fetch!(opts, :name)
    root_name = Keyword.get(opts, :root, edgedb_name)

    priv_dir = :code.priv_dir(otp_app)
    edgeql_queries_dir = Path.join(priv_dir, "edgeql")
    mix_recompilation_hook = define_mix_recompilation_hook(edgeql_queries_dir)

    quote location: :keep do
      unquote(mix_recompilation_hook)

      unquote(__MODULE__).__define_queries__(
        unquote(edgedb_name),
        unquote(root_name),
        unquote(edgeql_queries_dir),
        __ENV__
      )
    end
  end

  def __define_queries__(edgedb_name, root_name, queries_dir, env) do
    queries =
      [queries_dir, "*", "*.edgeql"]
      |> Path.join()
      |> Path.wildcard()

    base_parts = Path.split(queries_dir)

    queries
    |> Enum.reduce(%{}, fn path, acc ->
      query = File.read!(path)

      fun_name =
        path
        |> Path.rootname()
        |> Path.basename()

      dir_name = Path.dirname(path)
      new_module_attrs = Path.split(dir_name) -- base_parts

      module_name = Enum.map_join(new_module_attrs, ".", &Macro.camelize/1)

      if funs = acc[module_name] do
        funs = Map.put(funs, fun_name, query)
        Map.put(acc, module_name, funs)
      else
        Map.put(acc, module_name, %{fun_name => query})
      end
    end)
    |> Enum.each(fn {module_name, funs} ->
      module_def = EdgeDBEcto.Queries.__define_queries_module__(edgedb_name, funs)

      # this is safe since it will be used in compile time
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      module_name = Module.concat(root_name, module_name)
      Module.create(module_name, module_def, env)
    end)
  end

  def __define_queries_module__(edgedb_name, module_funs) do
    for {fun_name, query} <- module_funs do
      # this is safe since it will be used in compile time
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      fun_name = String.to_atom(fun_name)

      directives =
        query
        |> String.split("\n")
        |> Enum.reduce(%{"edgedb" => "query"}, fn line, directives ->
          case Regex.named_captures(@directive_regex, line) do
            %{"value" => ""} ->
              directives

            %{"directive" => directive, "value" => value} ->
              Map.put(directives, String.trim(directive), String.trim(value))

            _other ->
              directives
          end
        end)

      ":" <> driver_fun = directives["edgedb"]

      use_raising_convertion? = String.ends_with?(driver_fun, "!")

      # this is safe since it will be used in compile time
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      driver_fun = String.to_atom(driver_fun)

      mapper =
        if directives["mapper"] do
          # this is safe since it will be used in compile time
          # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
          String.to_atom("Elixir.#{directives["mapper"]}")
        else
          nil
        end

      quote do
        @doc """
        ```edgeql
        #{unquote(query)}
        ```
        """
        def unquote(fun_name)(params \\ [], opts \\ []) do
          edgedb_opts = Keyword.get(opts, :edgedb, [])
          conn = Keyword.get(edgedb_opts, :conn, unquote(edgedb_name))
          mapper = Keyword.get(edgedb_opts, :mapper, unquote(mapper))
          result = EdgeDB.unquote(driver_fun)(conn, unquote(query), params, opts)

          if unquote(use_raising_convertion?) do
            EdgeDBEcto.Convertable.convert!(mapper, result)
          else
            EdgeDBEcto.Convertable.convert(mapper, result)
          end
        end
      end
    end
  end

  defp define_mix_recompilation_hook(queries_dir) do
    quote do
      @edgeql_queries_dir unquote(queries_dir)

      @queries [@edgeql_queries_dir, "*", "*.edgeql"] |> Path.join() |> Path.wildcard()
      @queries_hash :erlang.md5(@queries)

      for query_path <- @queries do
        @external_resource query_path
      end

      def __mix_recompile__? do
        new_hash =
          [@edgeql_queries_dir, "*", "*.edgeql"]
          |> Path.join()
          |> Path.wildcard()
          |> :erlang.md5()

        new_hash != @queries_hash
      end
    end
  end
end

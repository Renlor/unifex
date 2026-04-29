defmodule Unifex do
  @moduledoc """
  Implementation of `Bundlex.Preprocessor`.

  When added to a native configuration in `Bundlex.Project`, equips the native with
  the Unifex native dependency and generated sources.
  """

  @behaviour Bundlex.Project.Preprocessor

  alias Bundlex.Native
  alias Bundlex.Project.Preprocessor
  alias Unifex.CodeGenerator
  alias Unifex.InterfaceIO

  @impl Preprocessor
  def preprocess_native_config(_name, _app, config) do
    unifex_deps = [unifex: :unifex]
    Keyword.update(config, :deps, unifex_deps, &(unifex_deps ++ &1))
  end

  @impl Preprocessor
  def preprocess_native(native) do
    %Native{app: app, name: name, interface: interface, language: language, sources: sources} =
      native

    generator =
      interface
      |> CodeGenerator.bundlex_interface()
      |> CodeGenerator.interface_generator()

    # The spec file lives in the same directory as the
    # user-declared sources, named `<name>.spec.exs`. Bundlex's
    # parse_native has already resolved sources to absolute paths
    # by this point (Path.join([src_path, src_base, source])), so
    # the spec directory is just the dirname of any user source.
    #
    # Deriving from the source paths avoids a project-tree walk
    # that previously globbed `**/?*.spec.exs` from the project
    # root -- on a typical Mix project that descends into
    # `_build/`, `deps/`, and any other unrelated subtrees,
    # paying tens of thousands of stat calls to find a handful of
    # specs. The walk's wall time scaled with project size and
    # could hit double-digit seconds on every compile.
    spec_dir =
      case sources do
        [first | _] ->
          Path.dirname(first)

        [] ->
          raise "Native #{inspect(name)} of app #{inspect(app)}: cannot resolve spec " <>
                  "directory because no sources were declared"
      end

    spec_file = Path.join(spec_dir, "#{name}.spec.exs")

    unless File.exists?(spec_file) do
      raise "Native #{inspect(name)} of app #{inspect(app)}: spec file not found at " <>
              "#{spec_file}. The spec is expected next to the user-declared sources."
    end

    source = InterfaceIO.out_path(name, spec_dir, generator, ".#{language}")
    %Native{native | sources: [source | native.sources]}
  end
end

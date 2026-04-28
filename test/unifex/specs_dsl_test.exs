defmodule Unifex.Specs.DSLTest do
  @moduledoc """
  Tests for the spec DSL parser, with focus on the function-form
  parameterized type parsing and arbitrary nesting support added on
  top of the legacy one-level shape.
  """

  use ExUnit.Case, async: true

  alias Unifex.Specs.DSL

  defp eval_dsl(code) do
    {_res, binds} =
      Code.eval_string(
        code,
        [{:unifex_config__, []}],
        make_env()
      )

    binds |> Keyword.fetch!(:unifex_config__) |> Enum.reverse()
  end

  defp make_env do
    {env, _} =
      Code.eval_quoted(
        quote do
          import Kernel, except: [@: 1]
          import Unifex.Specs.DSL
          %Macro.Env{__ENV__ | file: "test.spec.exs"}
        end
      )

    env
  end

  describe "parse_type_ast/1" do
    test "atom passes through" do
      assert DSL.parse_type_ast(quote(do: i32)) == :i32
      assert DSL.parse_type_ast(quote(do: str)) == :str
    end

    test "one-level function-form" do
      assert DSL.parse_type_ast(quote(do: vector(i32))) == {:vector, :i32}
      assert DSL.parse_type_ast(quote(do: optional(str))) == {:optional, :str}
    end

    test "two-level nesting" do
      assert DSL.parse_type_ast(quote(do: vector(optional(i32)))) ==
               {:vector, {:optional, :i32}}

      assert DSL.parse_type_ast(quote(do: optional(vector(i32)))) ==
               {:optional, {:vector, :i32}}
    end

    test "three-level nesting" do
      assert DSL.parse_type_ast(quote(do: vector(vector(optional(i32))))) ==
               {:vector, {:vector, {:optional, :i32}}}

      assert DSL.parse_type_ast(quote(do: optional(vector(vector(i32))))) ==
               {:optional, {:vector, {:vector, :i32}}}
    end

    test "four-level nesting" do
      assert DSL.parse_type_ast(quote(do: vector(vector(vector(optional(i32)))))) ==
               {:vector, {:vector, {:vector, {:optional, :i32}}}}
    end

    test "list literal" do
      assert DSL.parse_type_ast(quote(do: [i32])) == {:list, :i32}
    end
  end

  describe "spec/1 (function args)" do
    test "atom argument" do
      [function: quoted] = eval_dsl("spec(f(x :: i32) :: :ok)")
      assert {:f, [{:x, :i32}], _} = unquote_function(quoted)
    end

    test "one-level function-form arg" do
      [function: quoted] = eval_dsl("spec(f(x :: vector(i32)) :: :ok)")
      assert {:f, [{:x, {:vector, :i32}}], _} = unquote_function(quoted)
    end

    test "two-level nested arg" do
      [function: quoted] = eval_dsl("spec(f(x :: vector(optional(i32))) :: :ok)")
      assert {:f, [{:x, {:vector, {:optional, :i32}}}], _} = unquote_function(quoted)
    end

    test "three-level nested arg" do
      [function: quoted] =
        eval_dsl("spec(f(x :: vector(vector(optional(i32)))) :: :ok)")

      assert {:f, [{:x, {:vector, {:vector, {:optional, :i32}}}}], _} =
               unquote_function(quoted)
    end

    test "list-literal arg" do
      [function: quoted] = eval_dsl("spec(f(x :: [i32]) :: :ok)")
      assert {:f, [{:x, {:list, :i32}}], _} = unquote_function(quoted)
    end
  end

  describe "type/1 (struct fields)" do
    test "atom field" do
      [struct: quoted] =
        eval_dsl("type my_struct :: %My.S{field: i32}")

      assert {:my_struct, :"My.S", [{:field, :i32}]} = unquote_struct(quoted)
    end

    test "one-level function-form field" do
      [struct: quoted] =
        eval_dsl("type my_struct :: %My.S{field: vector(i32)}")

      assert {:my_struct, :"My.S", [{:field, {:vector, :i32}}]} =
               unquote_struct(quoted)
    end

    test "two-level nested field" do
      [struct: quoted] =
        eval_dsl("type my_struct :: %My.S{field: vector(optional(i32))}")

      assert {:my_struct, :"My.S", [{:field, {:vector, {:optional, :i32}}}]} =
               unquote_struct(quoted)
    end

    test "three-level nested field" do
      [struct: quoted] =
        eval_dsl("type my_struct :: %My.S{field: vector(vector(optional(i32)))}")

      assert {:my_struct, :"My.S",
              [{:field, {:vector, {:vector, {:optional, :i32}}}}]} =
               unquote_struct(quoted)
    end

    test "list-literal field" do
      [struct: quoted] =
        eval_dsl("type my_struct :: %My.S{field: [i32]}")

      assert {:my_struct, :"My.S", [{:field, {:list, :i32}}]} =
               unquote_struct(quoted)
    end
  end

  alias Unifex.CodeGenerator.Utils

  defp serializers do
    %{
      arg_serializer: fn type, name -> {:arg_ser, type, name} end,
      tuple_serializer: fn results -> {:tuple_ser, results} end
    }
  end

  describe "result-tuple positions (via Utils.generate_serialization)" do
    test "atom result" do
      ast =
        quote do
          x :: i32
        end

      {_serialized, meta} = Utils.generate_serialization(ast, serializers())
      assert meta == [arg: {:x, :i32}]
    end

    test "one-level function-form result" do
      ast =
        quote do
          x :: vector(i32)
        end

      {_, meta} = Utils.generate_serialization(ast, serializers())
      assert meta == [arg: {:x, {:vector, :i32}}]
    end

    test "two-level nested result" do
      ast =
        quote do
          x :: optional(vector(i32))
        end

      {_, meta} = Utils.generate_serialization(ast, serializers())
      assert meta == [arg: {:x, {:optional, {:vector, :i32}}}]
    end

    test "three-level nested result" do
      ast =
        quote do
          x :: vector(vector(optional(i32)))
        end

      {_, meta} = Utils.generate_serialization(ast, serializers())
      assert meta == [arg: {:x, {:vector, {:vector, {:optional, :i32}}}}]
    end
  end

  # Helpers: the DSL stores function/struct entries as quoted terms
  # (function via enquote/1, struct via Macro.escape/1). Unwrap them
  # to plain Elixir terms for assertion.

  defp unquote_function({:quote, _, [[do: term]]}), do: term
  defp unquote_function(term), do: term

  # The struct entry is stored via Macro.escape inside store_config's
  # quote block; once Code.eval_string runs that quote, the unquoted
  # value is the original tuple. Nothing to unwrap.
  defp unquote_struct(term), do: term
end

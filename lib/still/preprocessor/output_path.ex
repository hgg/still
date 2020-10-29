defmodule Still.Preprocessor.OutputPath do
  alias Still.Preprocessor

  use Preprocessor

  @impl true
  def render(%{variables: %{permalink: permalink}} = file) do
    %{file | output_file: permalink}
  end

  def render(%{input_file: input_file, extension: extension} = file) do
    output_file =
      input_file
      |> String.replace(Path.extname(input_file), extension)

    %{file | output_file: output_file}
  end

  def render(%{input_file: input_file} = file) do
    %{file | output_file: input_file}
  end
end

defmodule Still.Preprocessor.SlimeTest do
  use Still.Case

  alias Still.Preprocessor.Slime

  describe "render" do
    test "compiles a template" do
      slime = "p Still"
      file_path = "index.slime"

      %{content: html} = Slime.render(slime, %{file_path: file_path})

      assert html == "<p>Still</p>"
    end

    test "passes variables to the template" do
      slime = "p = title"
      file_path = "index.slime"
      title = "This is a test"

      %{content: html} = Slime.render(slime, %{file_path: file_path, title: title})

      assert html == "<p>This is a test</p>"
    end

    test "defines a render module" do
      slime = "p Still"
      file_path = "posts/index.slime"

      Slime.render(slime, %{file_path: file_path})

      assert {:module, _} = Code.ensure_compiled(Still.Preprocessor.Slime.Posts.Index)
    end
  end
end
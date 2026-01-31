defmodule FnXML.Parser.HTMLModeTest do
  use ExUnit.Case, async: true

  # Define a test HTML parser
  defmodule HTMLParser do
    use FnXML.Parser.Generator, edition: 5, mode: :html
  end

  # Define a test HTML parser with custom raw text elements
  defmodule CustomRawTextParser do
    use FnXML.Parser.Generator,
      edition: 5,
      mode: :html,
      raw_text_elements: [:script, :style, :textarea]
  end

  describe "mode configuration" do
    test "returns :html mode" do
      assert HTMLParser.mode() == :html
    end

    test "returns default raw_text_elements" do
      assert HTMLParser.raw_text_elements() == [:script, :style]
    end

    test "returns custom raw_text_elements" do
      assert CustomRawTextParser.raw_text_elements() == [:script, :style, :textarea]
    end
  end

  describe "boolean attributes" do
    test "parses single boolean attribute" do
      events = HTMLParser.parse("<input disabled>") |> Enum.to_list()

      assert Enum.any?(events, fn
               {:start_element, "input", attrs, _, _, _} ->
                 {"disabled", ""} in attrs

               _ ->
                 false
             end)
    end

    test "parses multiple boolean attributes" do
      events = HTMLParser.parse("<input disabled checked readonly>") |> Enum.to_list()

      {:start_element, "input", attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, "input", _, _, _, _}, &1))

      assert {"disabled", ""} in attrs
      assert {"checked", ""} in attrs
      assert {"readonly", ""} in attrs
    end

    test "parses boolean attribute with self-closing tag" do
      events = HTMLParser.parse("<input disabled/>") |> Enum.to_list()

      assert Enum.any?(events, fn
               {:start_element, "input", attrs, _, _, _} ->
                 {"disabled", ""} in attrs

               _ ->
                 false
             end)

      assert Enum.any?(events, fn
               {:end_element, "input", _, _, _} -> true
               _ -> false
             end)
    end

    test "parses boolean followed by valued attribute" do
      events = HTMLParser.parse("<input disabled name=\"x\">") |> Enum.to_list()

      {:start_element, "input", attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, "input", _, _, _, _}, &1))

      assert {"disabled", ""} in attrs
      assert {"name", "x"} in attrs
    end

    test "parses valued followed by boolean attribute" do
      events = HTMLParser.parse("<input name=\"x\" disabled>") |> Enum.to_list()

      {:start_element, "input", attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, "input", _, _, _, _}, &1))

      assert {"disabled", ""} in attrs
      assert {"name", "x"} in attrs
    end

    test "handles duplicate boolean attributes with error" do
      events = HTMLParser.parse("<input disabled disabled>") |> Enum.to_list()

      assert Enum.any?(events, &match?({:error, :duplicate_attribute, "disabled", _, _, _}, &1))
    end
  end

  describe "unquoted attribute values" do
    test "parses single unquoted attribute" do
      events = HTMLParser.parse("<div class=container>") |> Enum.to_list()

      {:start_element, "div", attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, "div", _, _, _, _}, &1))

      assert {"class", "container"} in attrs
    end

    test "parses multiple unquoted attributes" do
      events = HTMLParser.parse("<div class=container data-id=123>") |> Enum.to_list()

      {:start_element, "div", attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, "div", _, _, _, _}, &1))

      assert {"class", "container"} in attrs
      assert {"data-id", "123"} in attrs
    end

    test "parses mixed quoted and unquoted attributes" do
      events = HTMLParser.parse("<div class=foo id=\"bar\">") |> Enum.to_list()

      {:start_element, "div", attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, "div", _, _, _, _}, &1))

      assert {"class", "foo"} in attrs
      assert {"id", "bar"} in attrs
    end

    test "parses unquoted attribute with content" do
      events = HTMLParser.parse("<div class=foo>content</div>") |> Enum.to_list()

      assert Enum.any?(events, fn
               {:start_element, "div", attrs, _, _, _} ->
                 {"class", "foo"} in attrs

               _ ->
                 false
             end)

      assert Enum.any?(events, &match?({:characters, "content", _, _, _}, &1))
    end

    test "emits error for invalid characters in unquoted value" do
      events = HTMLParser.parse("<div class=foo<bar>") |> Enum.to_list()

      assert Enum.any?(events, &match?({:error, :invalid_unquoted_attr_char, "<", _, _, _}, &1))
    end

    test "parses unquoted attribute before boolean" do
      events = HTMLParser.parse("<input type=text disabled>") |> Enum.to_list()

      {:start_element, "input", attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, "input", _, _, _, _}, &1))

      assert {"type", "text"} in attrs
      assert {"disabled", ""} in attrs
    end
  end

  describe "raw text elements - script" do
    test "parses script with simple content" do
      events = HTMLParser.parse("<script>var x = 1;</script>") |> Enum.to_list()

      assert Enum.any?(events, &match?({:start_element, "script", [], _, _, _}, &1))
      assert Enum.any?(events, &match?({:characters, "var x = 1;", _, _, _}, &1))
      assert Enum.any?(events, &match?({:end_element, "script", _, _, _}, &1))
    end

    test "parses script with < character" do
      events = HTMLParser.parse("<script>if (a < b) {}</script>") |> Enum.to_list()

      assert Enum.any?(events, &match?({:characters, "if (a < b) {}", _, _, _}, &1))
    end

    test "parses script with > character" do
      events = HTMLParser.parse("<script>if (a > b) {}</script>") |> Enum.to_list()

      assert Enum.any?(events, &match?({:characters, "if (a > b) {}", _, _, _}, &1))
    end

    test "handles case-insensitive end tag" do
      events = HTMLParser.parse("<script>code</SCRIPT>") |> Enum.to_list()

      assert Enum.any?(events, &match?({:characters, "code", _, _, _}, &1))
      assert Enum.any?(events, &match?({:end_element, "script", _, _, _}, &1))
    end

    test "handles empty script element" do
      events = HTMLParser.parse("<script></script>") |> Enum.to_list()

      assert Enum.any?(events, &match?({:start_element, "script", [], _, _, _}, &1))
      assert Enum.any?(events, &match?({:end_element, "script", _, _, _}, &1))
      # No characters event for empty content
      refute Enum.any?(events, &match?({:characters, _, _, _, _}, &1))
    end

    test "handles partial end tag in content" do
      events = HTMLParser.parse("<script></scrip</script>") |> Enum.to_list()

      assert Enum.any?(events, &match?({:characters, "</scrip", _, _, _}, &1))
    end
  end

  describe "raw text elements - style" do
    test "parses style with content containing >" do
      events = HTMLParser.parse("<style>div > p { color: red; }</style>") |> Enum.to_list()

      assert Enum.any?(events, &match?({:start_element, "style", [], _, _, _}, &1))
      assert Enum.any?(events, &match?({:characters, "div > p { color: red; }", _, _, _}, &1))
      assert Enum.any?(events, &match?({:end_element, "style", _, _, _}, &1))
    end

    test "parses style with attributes" do
      events = HTMLParser.parse("<style type=text/css>body{}</style>") |> Enum.to_list()

      {:start_element, "style", attrs, _, _, _} =
        Enum.find(events, &match?({:start_element, "style", _, _, _, _}, &1))

      assert {"type", "text/css"} in attrs
    end
  end

  describe "raw text elements - nested in other elements" do
    test "parses script inside div" do
      events = HTMLParser.parse("<div><script>code</script></div>") |> Enum.to_list()

      tags =
        events
        |> Enum.filter(&match?({:start_element, _, _, _, _, _}, &1))
        |> Enum.map(fn {:start_element, tag, _, _, _, _} -> tag end)

      assert tags == ["div", "script"]

      assert Enum.any?(events, &match?({:characters, "code", _, _, _}, &1))
    end

    test "content after script continues normal parsing" do
      events = HTMLParser.parse("<div><script>x</script><p>text</p></div>") |> Enum.to_list()

      tags =
        events
        |> Enum.filter(&match?({:start_element, _, _, _, _, _}, &1))
        |> Enum.map(fn {:start_element, tag, _, _, _, _} -> tag end)

      assert tags == ["div", "script", "p"]

      assert Enum.any?(events, &match?({:characters, "text", _, _, _}, &1))
    end
  end

  describe "custom raw text elements" do
    test "parses textarea as raw text" do
      events = CustomRawTextParser.parse("<textarea>Hello < World</textarea>") |> Enum.to_list()

      assert Enum.any?(events, &match?({:characters, "Hello < World", _, _, _}, &1))
    end
  end

  describe "combined HTML features" do
    test "parses complex HTML fragment" do
      html = """
      <html>
        <head>
          <script>if (a < b) { alert('hi'); }</script>
          <style>div > p { color: red; }</style>
        </head>
        <body>
          <input type=text disabled placeholder="Enter name">
          <div class=container data-id=123>Content</div>
        </body>
      </html>
      """

      events = HTMLParser.parse(html) |> Enum.to_list()

      # Check for key elements
      assert Enum.any?(events, &match?({:start_element, "html", _, _, _, _}, &1))
      assert Enum.any?(events, &match?({:start_element, "script", _, _, _, _}, &1))
      assert Enum.any?(events, &match?({:start_element, "style", _, _, _, _}, &1))
      assert Enum.any?(events, &match?({:start_element, "input", _, _, _, _}, &1))
      assert Enum.any?(events, &match?({:start_element, "div", _, _, _, _}, &1))

      # Check script content preserved < and >
      assert Enum.any?(events, fn
               {:characters, content, _, _, _} ->
                 String.contains?(content, "if (a < b)")

               _ ->
                 false
             end)

      # Check style content preserved >
      assert Enum.any?(events, fn
               {:characters, content, _, _, _} ->
                 String.contains?(content, "div > p")

               _ ->
                 false
             end)

      # Check boolean attribute on input
      input_event = Enum.find(events, &match?({:start_element, "input", _, _, _, _}, &1))
      {:start_element, "input", input_attrs, _, _, _} = input_event
      assert {"disabled", ""} in input_attrs
      assert {"type", "text"} in input_attrs

      # Check unquoted attributes on div
      div_event = Enum.find(events, &match?({:start_element, "div", _, _, _, _}, &1))
      {:start_element, "div", div_attrs, _, _, _} = div_event
      assert {"class", "container"} in div_attrs
      assert {"data-id", "123"} in div_attrs
    end
  end
end

defmodule XMLStreamTools.ParserTest do
  use ExUnit.Case
  doctest XMLStreamTools.Parser

  def parse_xml(xml) do
    xml
    |> XMLStreamTools.Parser.parse()
    |> Enum.map(fn x -> x end)
  end

  test "test 1" do
    result = parse_xml("<ns:foo a=\"1\" a:b='2'>bar</ns:foo>")
    # IO.inspect(result)
    assert result == [
             open_tag: [
               tag: "foo",
               namespace: "ns",
               attr: [{"a", "1"}, {"a:b", "2"}],
               loc: {{1, 0}, 1}
             ],
             text: ["bar", {:loc, {{1, 0}, 25}}],
             close_tag: [tag: "foo", namespace: "ns", loc: {{1, 0}, 27}]
           ]
  end

  test "test 2" do
    result = parse_xml("<ns:foo a='1'><bar>message</bar></ns:foo>")
    # IO.inspect(result)
    assert result == [
             {:open_tag, [tag: "foo", namespace: "ns", attr: [{"a", "1"}], loc: {{1, 0}, 1}]},
             {:open_tag, [tag: "bar", loc: {{1, 0}, 15}]},
             {:text, ["message", {:loc, {{1, 0}, 26}}]},
             {:close_tag, [tag: "bar", loc: {{1, 0}, 28}]},
             {:close_tag, [tag: "foo", namespace: "ns", loc: {{1, 0}, 34}]}
           ]
  end

  test "soap" do
    input = "<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:soapenc=\"http://schemas.xmlsoap.org/soap/encoding/\" xmlns:tns=\"http://www.witsml.org/wsdl/120\" xmlns:types=\"http://www.witsml.org/wsdl/120/encodedTypes\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><soap:Body soap:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><q1:WMLS_GetVersion xmlns:q1=\"http://www.witsml.org/message/120\"/></soap:Body></soap:Envelope>"

    result = parse_xml(input)
    assert result == [
      {
        :open_tag, [
          tag: "Envelope",
          namespace: "soap",
          attr: [
            {"xmlns:soap", "http://schemas.xmlsoap.org/soap/envelope/"},
            {"xmlns:soapenc", "http://schemas.xmlsoap.org/soap/encoding/"},
            {"xmlns:tns", "http://www.witsml.org/wsdl/120"},
            {"xmlns:types", "http://www.witsml.org/wsdl/120/encodedTypes"},
            {"xmlns:xsd", "http://www.w3.org/2001/XMLSchema"},
            {"xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance"}
          ],
          loc: {{1, 0}, 1}
        ]
      },
      {
        :open_tag, [
          tag: "Body",
          namespace: "soap",
          attr: [{"soap:encodingStyle", "http://schemas.xmlsoap.org/soap/encoding/"}],
          loc: {{1, 0}, 329}
        ]
      },
      {
        :open_tag, [
          tag: "WMLS_GetVersion",
          namespace: "q1",
          attr: [{"xmlns:q1", "http://www.witsml.org/message/120"}],
          close: true,
          loc: {{1, 0}, 403}
        ]
      },
      {:close_tag, [tag: "Body", namespace: "soap", loc: {{1, 0}, 470}]},
      {:close_tag, [tag: "Envelope", namespace: "soap", loc: {{1, 0}, 482}]}
    ]
  end
end

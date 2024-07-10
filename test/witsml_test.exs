defmodule WITSML_Test do
  use ExUnit.Case

  alias FnXML.Stream.NativeDataStruct, as: NDS
  
  @request_1 """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/" xmlns:tns="http://www.witsml.org/wsdl/120" xmlns:types="http://www.witsml.org/wsdl/120/encodedTypes" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <soap:Body soap:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <q1:WMLS_GetFromStore xmlns:q1="http://www.witsml.org/message/120">
        <WMLtypeIn xsi:type="xsd:string">log</WMLtypeIn>
        <QueryIn xsi:type="xsd:string">&lt;logs xmlns="http://www.witsml.org/schemas/131" version="1.3.1.1"&gt;
      &lt;log uidWell="us_28744578" uidWellbore="us_28744578_wb1" uid="us_28744578_wb1_log_hfll_time_1s"&gt;
          &lt;name /&gt;
          &lt;startDateTimeIndex /&gt;
          &lt;endDateTimeIndex /&gt;
      &lt;/log&gt;
      &lt;/logs&gt;</QueryIn>
          <OptionsIn xsi:type="xsd:string">returnElements=requested</OptionsIn>
        </q1:WMLS_GetFromStore>
      </soap:Body>
    </soap:Envelope>
  """

  describe "test WITSML decode" do
    test "witsml decode" do

      result = 
        FnXML.Parser.parse(@request_1)
        |> FnXML.Stream.filter_namespaces(["soap"], exclude: true)
        |> FnXML.Stream.filter_ws()
        |> Enum.map(fn x -> x end)

      IO.puts("")
      IO.puts("#{FnXML.Stream.to_xml(result, pretty: true) |> Enum.join()}")

      NDS.DecoderDefault.decode(result, [])
      |> Enum.map(fn x -> x end)
      |> IO.inspect()
    end
  end
end

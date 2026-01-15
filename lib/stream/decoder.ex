defmodule FnXML.Stream.Decoder do
  @moduledoc """
  A simple XML stream decoder, implemented using behaviours.

  Event formats:
  - `{:start_document, nil}` - Document start marker
  - `{:end_document, nil}` - Document end marker
  - `{:start_element, tag, attrs, loc}` - Opening tag with attributes
  - `{:end_element, tag}` or `{:end_element, tag, loc}` - Closing tag
  - `{:characters, content, loc}` - Text content
  - `{:comment, content, loc}` - Comment
  - `{:prolog, "xml", attrs, loc}` - XML prolog
  - `{:processing_instruction, name, content, loc}` - Processing instruction
  """

  @callback handle_prolog(element :: tuple, path :: list, acc :: list, opts :: list) :: list
  @callback handle_open(element :: tuple, path :: list, acc :: list, opts :: list) :: list
  @callback handle_close(element :: tuple, path :: list, acc :: list, opts :: list) :: list
  @callback handle_text(element :: tuple, path :: list, acc :: list, opts :: list) :: list
  @callback handle_comment(element :: tuple, path :: list, acc :: list, opts :: list) :: list
  @callback handle_proc_inst(element :: tuple, path :: list, acc :: list, opts :: list) :: list

  def decode(stream, module \\ FnXML.Stream.Decoder.Default, opts \\ []) do
    FnXML.Stream.transform(stream, fn
      {:start_document, _}, _path, acc ->
        acc

      {:end_document, _}, _path, acc ->
        acc

      # 6-tuple prolog (from parser)
      {:prolog, tag, attrs, line, ls, pos}, path, acc ->
        module.handle_prolog({:prolog, tag, attrs, {line, ls, pos}}, path, acc, opts)

      # 4-tuple prolog (normalized)
      {:prolog, _, _, _} = elem, path, acc ->
        module.handle_prolog(elem, path, acc, opts)

      # 6-tuple start_element (from parser)
      {:start_element, tag, attrs, line, ls, pos}, path, acc ->
        module.handle_open({:start_element, tag, attrs, {line, ls, pos}}, path, acc, opts)

      # 4-tuple start_element (normalized)
      {:start_element, _, _, _} = elem, path, acc ->
        module.handle_open(elem, path, acc, opts)

      # 5-tuple end_element (from parser)
      {:end_element, tag, line, ls, pos}, path, acc ->
        module.handle_close({:end_element, tag, {line, ls, pos}}, path, acc, opts)

      # 3-tuple end_element (normalized)
      {:end_element, _, _} = elem, path, acc ->
        module.handle_close(elem, path, acc, opts)

      # 2-tuple end_element
      {:end_element, _} = elem, path, acc ->
        module.handle_close(elem, path, acc, opts)

      # 5-tuple characters (from parser)
      {:characters, content, line, ls, pos}, path, acc ->
        module.handle_text({:characters, content, {line, ls, pos}}, path, acc, opts)

      # 3-tuple characters (normalized)
      {:characters, _, _} = elem, path, acc ->
        module.handle_text(elem, path, acc, opts)

      # 5-tuple comment (from parser)
      {:comment, content, line, ls, pos}, path, acc ->
        module.handle_comment({:comment, content, {line, ls, pos}}, path, acc, opts)

      # 3-tuple comment (normalized)
      {:comment, _, _} = elem, path, acc ->
        module.handle_comment(elem, path, acc, opts)

      # 6-tuple processing_instruction (from parser)
      {:processing_instruction, name, content, line, ls, pos}, path, acc ->
        module.handle_proc_inst({:processing_instruction, name, content, {line, ls, pos}}, path, acc, opts)

      # 4-tuple processing_instruction (normalized)
      {:processing_instruction, _, _, _} = elem, path, acc ->
        module.handle_proc_inst(elem, path, acc, opts)

      # Ignore other events (space, cdata, dtd, etc.)
      _, _path, acc ->
        acc
    end)
  end
end

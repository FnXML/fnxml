defmodule FnXML.Stream.Decoder do
  @moduledoc """
  A simple XML stream decoder, implemented using behaviours.

  Event formats:
  - `{:doc_start, nil}` - Document start marker
  - `{:doc_end, nil}` - Document end marker
  - `{:open, tag, attrs, loc}` - Opening tag with attributes
  - `{:close, tag}` or `{:close, tag, loc}` - Closing tag
  - `{:text, content, loc}` - Text content
  - `{:comment, content, loc}` - Comment
  - `{:prolog, "xml", attrs, loc}` - XML prolog
  - `{:proc_inst, name, content, loc}` - Processing instruction
  """

  @callback handle_prolog(element :: tuple, path :: list, acc :: list, opts :: list) :: list
  @callback handle_open(element :: tuple, path :: list, acc :: list, opts :: list) :: list
  @callback handle_close(element :: tuple, path :: list, acc :: list, opts :: list) :: list
  @callback handle_text(element :: tuple, path :: list, acc :: list, opts :: list) :: list
  @callback handle_comment(element :: tuple, path :: list, acc :: list, opts :: list) :: list
  @callback handle_proc_inst(element :: tuple, path :: list, acc :: list, opts :: list) :: list

  def decode(stream, module \\ FnXML.Stream.Decoder.Default, opts \\ []) do
    FnXML.Stream.transform(stream, fn
      {:doc_start, _}, _path, acc -> acc
      {:doc_end, _}, _path, acc -> acc
      {:prolog, _, _, _} = elem, path, acc -> module.handle_prolog(elem, path, acc, opts)
      {:open, _, _, _} = elem, path, acc -> module.handle_open(elem, path, acc, opts)
      {:close, _} = elem, path, acc -> module.handle_close(elem, path, acc, opts)
      {:close, _, _} = elem, path, acc -> module.handle_close(elem, path, acc, opts)
      {:text, _, _} = elem, path, acc -> module.handle_text(elem, path, acc, opts)
      {:comment, _, _} = elem, path, acc -> module.handle_comment(elem, path, acc, opts)
      {:proc_inst, _, _, _} = elem, path, acc -> module.handle_proc_inst(elem, path, acc, opts)
    end)
  end
end

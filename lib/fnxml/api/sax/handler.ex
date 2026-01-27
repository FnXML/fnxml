defmodule FnXML.API.SAX.Handler do
  @moduledoc """
  Default SAX handler implementation with overridable callbacks.

  Use this module to create SAX handlers with default implementations
  for all callbacks. Override only the callbacks you need.

  ## Usage

      defmodule MyHandler do
        use FnXML.SAX.Handler

        @impl true
        def start_element(_uri, local_name, _qname, _attrs, state) do
          {:ok, [local_name | state]}
        end
      end

      {:ok, elements} = FnXML.SAX.parse("<a><b/></a>", MyHandler, [])
      # elements => ["b", "a"]

  ## Default Behavior

  By default, all callbacks simply return `{:ok, state}` unchanged:

  - `start_document/1` - Pass through
  - `end_document/1` - Pass through
  - `start_element/5` - Pass through
  - `end_element/4` - Pass through
  - `characters/2` - Pass through
  - `comment/2` - Pass through
  - `processing_instruction/3` - Pass through
  - `start_prefix_mapping/3` - Pass through
  - `end_prefix_mapping/2` - Pass through
  - `ignorable_whitespace/2` - Pass through
  - `error/3` - Returns `{:error, {reason, location}}`

  ## Example: Element Counter

      defmodule CounterHandler do
        use FnXML.SAX.Handler

        @impl true
        def start_element(_uri, _local, _qname, _attrs, count) do
          {:ok, count + 1}
        end
      end

      {:ok, 3} = FnXML.SAX.parse("<a><b/><c/></a>", CounterHandler, 0)

  ## Example: Text Collector

      defmodule TextCollector do
        use FnXML.SAX.Handler

        @impl true
        def characters(text, acc) do
          {:ok, [text | acc]}
        end

        @impl true
        def end_document(acc) do
          {:ok, acc |> Enum.reverse() |> Enum.join()}
        end
      end

      {:ok, "Hello World"} = FnXML.SAX.parse("<root>Hello <b>World</b></root>", TextCollector, [])

  ## Example: Early Termination

      defmodule FindFirst do
        use FnXML.SAX.Handler

        @impl true
        def start_element(_uri, local, _qname, _attrs, state) do
          if local == "target" do
            {:halt, :found}
          else
            {:ok, state}
          end
        end
      end

      {:ok, :found} = FnXML.SAX.parse("<root><other/><target/><more/></root>", FindFirst, nil)
  """

  @doc """
  Use this module to create a SAX handler with default implementations.

  All callbacks are implemented with pass-through behavior and can be
  overridden as needed.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour FnXML.SAX

      @impl true
      def start_document(state), do: {:ok, state}

      @impl true
      def end_document(state), do: {:ok, state}

      @impl true
      def start_element(_uri, _local_name, _qname, _attrs, state), do: {:ok, state}

      @impl true
      def end_element(_uri, _local_name, _qname, state), do: {:ok, state}

      @impl true
      def characters(_chars, state), do: {:ok, state}

      @impl true
      def comment(_text, state), do: {:ok, state}

      @impl true
      def processing_instruction(_target, _data, state), do: {:ok, state}

      @impl true
      def start_prefix_mapping(_prefix, _uri, state), do: {:ok, state}

      @impl true
      def end_prefix_mapping(_prefix, state), do: {:ok, state}

      @impl true
      def ignorable_whitespace(_chars, state), do: {:ok, state}

      @impl true
      def error(reason, location, _state), do: {:error, {reason, location}}

      defoverridable start_document: 1,
                     end_document: 1,
                     start_element: 5,
                     end_element: 4,
                     characters: 2,
                     comment: 2,
                     processing_instruction: 3,
                     start_prefix_mapping: 3,
                     end_prefix_mapping: 2,
                     ignorable_whitespace: 2,
                     error: 3
    end
  end
end

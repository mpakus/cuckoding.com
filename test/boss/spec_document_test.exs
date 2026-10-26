defmodule Boss.Projects.SpecDocumentTest do
  use ExUnit.Case, async: true
  alias Boss.Projects.SpecDocument

  test "plain Markdown keeps every byte and takes the first body H1" do
    source = "Intro  \n## Smaller\n# First title ###\n# Later\n"
    assert {:ok, attrs} = SpecDocument.parse("nested/001-task.md", source)

    assert attrs == %{
             relative_path: "nested/001-task.md",
             original_text: source,
             title: "First title"
           }
  end

  test "empty or heading-free Markdown falls back to the filename stem" do
    for source <- ["", "  \n", "#", "# ###", "## Only H2", "#not a heading", "    # Code"] do
      assert {:ok, %{title: "001-task", original_text: ^source}} =
               SpecDocument.parse("nested/001-task.md", source)
    end
  end

  test "H1-looking lines inside fenced code are not titles" do
    source =
      "````markdown\n# Code\n```\n# Still code\n````\n~~~ text\n# More code\n~~~\n   # Real title\n"

    assert {:ok, %{title: "Real title"}} = SpecDocument.parse("file.md", source)
  end

  test "BOM and CRLF are accepted while the original source stays untouched" do
    source = "\uFEFF---\r\nid: stable-id\r\n---\r\n# Заголовок\r\n"

    assert {:ok, %{explicit_id: "stable-id", title: "Заголовок", original_text: ^source}} =
             SpecDocument.parse("file.md", source)

    assert {:ok, %{title: "Plain BOM"}} = SpecDocument.parse("file.md", "\uFEFF# Plain BOM")
  end

  test "valid YAML fields override title and unknown metadata stays source-only" do
    source =
      "---\nid: '42'\ntitle: \"Chosen title\"\npriority: high\ndepends_on: [other]\n---\n# Body title\n"

    assert {:ok, attrs} = SpecDocument.parse("file.md", source)

    assert attrs == %{
             relative_path: "file.md",
             original_text: source,
             explicit_id: "42",
             title: "Chosen title"
           }
  end

  test "quoted markup remains plain title text and literal alias characters remain strings" do
    source = "---\nid: '*not-an-alias'\ntitle: '<script>alert(1)</script>'\n---\n"

    assert {:ok, %{explicit_id: "*not-an-alias", title: "<script>alert(1)</script>"}} =
             SpecDocument.parse("file.md", source)
  end

  test "frontmatter is recognized only on the opening line" do
    source = "\n---\nid: ignored\n---\n# Body"
    assert {:ok, %{title: "Body"} = attrs} = SpecDocument.parse("file.md", source)
    refute Map.has_key?(attrs, :explicit_id)
  end

  test "empty, scalar and sequence frontmatter are rejected" do
    for yaml <- ["", "# comment only", "{}", "[]", "null", "value", "- one\n- two"] do
      assert {:error, message} = SpecDocument.parse("file.md", frontmatter(yaml))
      assert is_binary(message)
    end
  end

  test "malformed and unclosed YAML fail instead of falling back to the heading" do
    for source <- [frontmatter("id: [unterminated"), "---\nid: ok\n# Heading", "---"] do
      assert {:error, _} = SpecDocument.parse("file.md", source)
    end
  end

  test "multiple YAML documents are rejected" do
    for yaml <- ["id: one\n...\nid: two", "id: one\n--- id: two"] do
      assert {:error, _} = SpecDocument.parse("file.md", frontmatter(yaml))
    end
  end

  test "duplicate keys at any depth fail, including quoted-equivalent and unknown keys" do
    for yaml <- [
          "id: one\nid: two",
          "id: one\n\"id\": two",
          "unknown: 1\nunknown: 2",
          "unknown: {nested: 1, nested: 2}"
        ] do
      assert {:error, message} = SpecDocument.parse("file.md", frontmatter(yaml))
      assert message =~ "duplicate"
    end
  end

  test "ID and title must be nonempty scalar strings, not coercible YAML values" do
    for value <- ["42", "true", "null", "[]", "{}", "''", "'   '"] do
      assert {:error, _} = SpecDocument.parse("file.md", frontmatter("id: " <> value))
      assert {:error, _} = SpecDocument.parse("file.md", frontmatter("title: " <> value))
    end

    assert {:error, _} = SpecDocument.parse("file.md", frontmatter("id: ' padded '"))
    assert {:error, _} = SpecDocument.parse("file.md", frontmatter("id: |\n  two\n  lines"))

    assert {:error, _} =
             SpecDocument.parse(
               "file.md",
               frontmatter("id: '" <> String.duplicate("x", 201) <> "'")
             )

    assert {:error, _} =
             SpecDocument.parse(
               "file.md",
               frontmatter("title: '" <> String.duplicate("x", 201) <> "'")
             )
  end

  test "aliases, unknown tags and merge keys fail without changing their meaning" do
    for yaml <- [
          "id: &name shared\ntitle: *name",
          "unknown: &base {wrong: value}\nid: *base",
          "id: !custom unsafe",
          "id: !<tag:yamerl,2012:atom> hostile_unique_atom",
          "base: &base {id: inherited}\n<<: *base"
        ] do
      assert {:error, _} = SpecDocument.parse("file.md", frontmatter(yaml))
    end
  end

  test "YAML binary tags cannot become string metadata, even when decoded bytes are UTF-8" do
    for field <- ["title", "id", "unknown"],
        tag <- ["!!binary", "!<tag:yaml.org,2002:binary>"],
        encoded <- ["/w==", "YXV0aA=="] do
      assert {:error, message} =
               SpecDocument.parse("file.md", frontmatter("#{field}: #{tag} #{encoded}"))

      assert message =~ "binary"
    end

    assert {:ok, %{explicit_id: "YXV0aA==", title: "!!binary /w=="}} =
             SpecDocument.parse(
               "file.md",
               frontmatter("id: !!str YXV0aA==\ntitle: '!!binary /w=='")
             )
  end

  test "string-looking atoms remain strings and arbitrary metadata keys never become atoms" do
    key = "boss_document_atom_" <> Base.encode16(:crypto.strong_rand_bytes(12))
    assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
    source = frontmatter(":#{key}: :#{key}\nid: :#{key}")
    assert {:ok, %{explicit_id: id}} = SpecDocument.parse("file.md", source)
    assert id == ":" <> key
    assert_raise ArgumentError, fn -> String.to_existing_atom(key) end

    assert {:error, _} =
             SpecDocument.parse("file.md", frontmatter("id: !<tag:yamerl,2012:atom> #{key}"))

    assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
  end

  test "document and header byte limits, UTF-8 and NUL are enforced" do
    assert {:ok, _} = SpecDocument.parse("file.md", String.duplicate("x", 1_048_576))

    for source <- [String.duplicate("x", 1_048_577), <<255>>, "bad\0text", nil] do
      assert {:error, _} = SpecDocument.parse("file.md", source)
    end

    assert {:ok, _} =
             SpecDocument.parse(
               "file.md",
               frontmatter("unknown: " <> String.duplicate("x", 16_374))
             )

    assert {:error, message} =
             SpecDocument.parse(
               "file.md",
               frontmatter("unknown: " <> String.duplicate("x", 16_384))
             )

    assert message =~ "16 KiB"
  end

  test "recursive or expanding aliases are bounded and do not poison later parses" do
    bomb =
      Enum.reduce(1..12, "a0: &a0 [x, x, x, x]\n", fn n, text ->
        text <> "a#{n}: &a#{n} [" <> Enum.map_join(1..8, ",", fn _ -> "*a#{n - 1}" end) <> "]\n"
      end)

    started = System.monotonic_time(:millisecond)
    assert {:error, _} = SpecDocument.parse("file.md", frontmatter(bomb))
    assert System.monotonic_time(:millisecond) - started < 2000
    assert {:error, _} = SpecDocument.parse("file.md", frontmatter("a: &a [*a]"))
    assert {:ok, %{title: "Still alive"}} = SpecDocument.parse("file.md", "# Still alive")
    refute_received {_ref, {:ok, _}}
  end

  test "deep YAML is bounded by worker resources without crashing the caller" do
    started = System.monotonic_time(:millisecond)

    assert {:error, "Frontmatter exceeds parser resource limits."} =
             SpecDocument.parse("file.md", deeply_nested())

    assert System.monotonic_time(:millisecond) - started < 2000
    assert {:ok, _} = SpecDocument.parse("file.md", frontmatter("id: after-limit"))
  end

  test "the parser worker still terminates when its caller dies" do
    caller =
      spawn(fn ->
        receive do
          :start -> SpecDocument.parse("file.md", deeply_nested())
        end
      end)

    on_exit(fn -> Process.exit(caller, :kill) end)
    :erlang.trace(caller, true, [:procs])
    send(caller, :start)
    assert_receive {:trace, ^caller, :spawn, worker, _}, 1000
    on_exit(fn -> Process.exit(worker, :kill) end)

    assert {:max_heap_size, %{kill: true, error_logger: false}} =
             Process.info(worker, :max_heap_size)

    monitor = Process.monitor(worker)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2000
  end

  defp deeply_nested do
    frontmatter("unknown: " <> String.duplicate("[", 7000) <> "x" <> String.duplicate("]", 7000))
  end

  defp frontmatter(yaml), do: "---\n" <> yaml <> "\n---\n# Body title\n"
end

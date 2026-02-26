# AsciiDoc Specification (Draft)

Use this as a reference for implementing the parser.

## 1. Document Structure

### 1.1 Headers
*   **Level 0**: `= Document Title`
    *   Creates the document title. Only one allowed per document (unless `doctype` is `book`).
    *   Must be the first block.
    *   Can have attributes immediately following: `:attr: value`.
*   **Level 1-5**: `== Level 1`, `=== Level 2`, etc.
    *   Standard section headers.
    *   Must be followed by at least one space before the title text.
    *   Can have role/ID attributes: `[#id.role]` before the header.

### 1.2 Blocks
*   **Paragraphs**:
    *   Contiguous lines of text separated by at least one blank line.
    *   First line determines indentation if any.
    *   Can span multiple lines; newlines are treated as spaces by default.
    *   Hard line breaks: ` +` at the end of a line.

*   **Delimited Blocks**:
    *   Start and end with a delimiter line of 4 or more characters.
    *   **Listing**: `----` (4 hyphens). Preserves formatting. `[source,language]` attribute enables syntax highlighting.
    *   **Literal**: `....` (4 dots). Indented literal content.
    *   **Sidebar**: `****` (4 asterisks). Visually distinct box.
    *   **Example**: `====` (4 equals signs). Comprehensive block for complex content.
    *   **Quote**: `____` (4 underscores). Blockquote with attribution.
    *   **Passthrough**: `++++` (4 plus signs). Raw content passed to backend (e.g., HTML).
    *   **Open**: `--` (2 hyphens). Anonymous block container.
    *   **Comment**: `////` (4 slashes). Block comments not rendered.

*   **Lists**:
    *   **Unordered**:
        *   `*` (Level 1), `**` (Level 2), `***` (Level 3), etc.
        *   Must be followed by a space.
        *   Can contain multiple paragraphs if indented or using list continuation `+`.
    *   **Ordered**:
        *   `.` (Level 1), `..` (Level 2), `...` (Level 3), etc.
        *   Automatic numbering (arabic, loweralpha, lowerroman, upperalpha, upperroman).
    *   **Checklist**:
        *   `* [ ]` (Unchecked), `* [x]` or `* [*]` (Checked).
        *   Valid only in unordered lists.
    *   **Description**:
        *   `Term:: Definition` (Double colon).
        *   `Term::: Definition` (Triple colon).
        *   `Term:::: Definition` (Quadruple colon).
        *   Definition can be on the same line or next line.

*   **Tables**:
    *   Delimited by `|===`.
    *   Columns separated by `|`.
    *   Header row separated from body by an empty line (often implicitly the first row if `[options="header"]` or explicitly marked).
    *   Column specifiers: `[cols="1,2,1"]`.
    *   Cell styles: `a|` (AsciiDoc content), `e|` (Emphasis), `s|` (Strong), `l|` (Literal), `m|` (Monospace), `h|` (Header).

### 1.3 Admonitions
*   **Simple**: `NOTE: Text...`
*   **Block**: `[NOTE]` followed by an example block `====`.
*   Standard types: `NOTE`, `TIP`, `IMPORTANT`, `WARNING`, `CAUTION`.

### 1.4 Inline Formatting
*   **Bold**: `*text*` (constrained) or `**t**ext` (unconstrained).
*   **Italic**: `_text_` (constrained) or `__t__ext` (unconstrained).
*   **Monospace**: `` `text` `` (constrained) or `` ``t``ext `` (unconstrained).
*   **Superscript**: `^text^`.
*   **Subscript**: `~text~`.
*   **Highlight**: `#text#`.
*   **Passthrough**: `+++text+++` or `$$text$$`.

### 1.5 Macros
*   **links**: `http://example.com[Label]`, `link:page.html[Label]`.
*   **images**: `image::target.jpg[alt,width,height]` (block), `image:target.jpg[alt]` (inline).
*   **includes**: `include::filename.adoc[]` (imports content).
*   **keyboard**: `kbd:[Ctrl+C]`.
*   **button**: `btn:[Save]`.
*   **menu**: `menu:File[Open]`.

### 1.6 Attributes
*   **Definition**: `:name: value` (Header or inline).
*   **Reference**: `{name}`.
*   **Conditional**: `ifdef::name[]`, `ifndef::name[]`, `ifeval::[]`.
*   **Intrinsic**: `{author}`, `{email}`, `{revnumber}`, `{revdate}`, `{toc}`, `{sectnums}`.

## 2. Parsing Approach

1.  **Tokenizer/Lexer**:
    *   Identify line types: Header, Block Delimiter, List Item, Attribute Entry, Text.
    *   Handle block context tracking (nested blocks).

2.  **Parser**:
    *   Process line-by-line or chunk-by-chunk.
    *   Maintain a stack of open blocks.
    *   When a delimiter is encountered:
        *   If it matches the top of the stack -> Close block.
        *   Else -> Open new block.
    *   Handle indentation for list continuations.

3.  **AST**:
    *   `Document` (Root)
    *   `Section` (Container)
    *   `Block` (Generic container or leaf)
        *   `Paragraph`
        *   `Listing`, `Literal`, `Sidebar`, etc.
        *   `List`, `ListItem`, `DList`, `DListItem`
        *   `Table`, `Row`, `Cell`
    *   `Inline` (Span elements within text)

4.  **Converter**:
    *   Visitor pattern or recursive traversal.
    *   Backend-specific generation (HTML5, PDF, Manpage).

## 3. Implementation Priorities for `asciidoctor-d`

1.  **Core Structure**: Headers, Sections, Paragraphs. (Done)
2.  **Basic Lists**: Unordered, Ordered, Checklists. (Next)
3.  **Delimited Blocks**: Source, Quote, Sidebar.
4.  **Inline Formatting**: Bold, Italic, Code, Links.
5.  **Attributes**: Basic substitution.
6.  **Tables**: Simple grid.

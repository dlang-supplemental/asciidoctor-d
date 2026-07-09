module asciidoctor.parser;

import asciidoctor.ast;
import asciidoctor.util;
import std.algorithm;
import std.array;
import std.conv : to;
import std.file : exists, isFile, readText;
import std.path : buildNormalizedPath, dirName;
import std.regex;
import std.string;

class Parser
{
    private string[] lines;
    private size_t currentLine;
    private Document doc;
    private string baseDir;
    private string[] attrListPending;
    private string blockTitlePending;

    this(string source, string baseDir = ".")
    {
        this.lines = source.splitLines();
        this.currentLine = 0;
        this.baseDir = baseDir;
    }

    Document parse()
    {
        doc = new Document();
        parseDocumentHeader();
        while (hasMoreLines())
            parseOneBlock(doc);
        return doc;
    }

    void parseInto(Document document, Block parent)
    {
        this.doc = document;
        while (hasMoreLines())
            parseOneBlock(parent);
    }

    private void parseDocumentHeader()
    {
        skipBlankLines();
        if (!hasMoreLines())
            return;

        int level;
        string title;
        if (!matchSectionTitle(peekLine().strip, level, title) || level != 0)
            return;

        doc.doctitle = title;
        advanceLine();

        if (hasMoreLines() && isAuthorLine(peekLine()))
        {
            doc.authors = peekLine().strip;
            doc.docAttributes["author"] = doc.authors;
            advanceLine();
        }

        if (hasMoreLines() && isRevisionLine(peekLine()))
        {
            parseRevisionLine(peekLine().strip, doc);
            advanceLine();
        }

        while (hasMoreLines())
        {
            auto l = peekLine();
            if (l.strip.empty)
            {
                advanceLine();
                break;
            }
            string name, value;
            if (matchAttrEntry(l, name, value))
            {
                doc.docAttributes[name] = value;
                advanceLine();
                continue;
            }
            break;
        }
    }

    private void parseOneBlock(Block parent)
    {
        skipBlankLines();
        if (!hasMoreLines())
            return;

        auto stripped = peekLine().strip;

        if (stripped.startsWith("[") && stripped.endsWith("]") && !stripped.startsWith("[["))
        {
            attrListPending ~= stripped[1 .. $ - 1];
            advanceLine();
            return;
        }

        if (isBlockTitleLine(stripped))
        {
            blockTitlePending = stripped[1 .. $];
            advanceLine();
            return;
        }

        if (stripped.startsWith("//") && !stripped.startsWith("////"))
        {
            advanceLine();
            return;
        }

        string attrName, attrValue;
        if (matchAttrEntry(stripped, attrName, attrValue))
        {
            doc.docAttributes[attrName] = attrValue;
            advanceLine();
            return;
        }

        // Thematic break: ''' (also --- / *** when not a 4+ delimiter)
        if (stripped == "'''" || stripped == "---" || stripped == "***")
        {
            advanceLine();
            auto hr = new Block();
            hr.context = "thematic_break";
            applyPendingMeta(hr);
            parent.blocks ~= hr;
            return;
        }

        if (stripped == "<<<")
        {
            advanceLine();
            auto pb = new Block();
            pb.context = "page_break";
            applyPendingMeta(pb);
            parent.blocks ~= pb;
            return;
        }

        // Block anchor [[id]] or [[id,reftext]]
        if (stripped.startsWith("[[") && stripped.endsWith("]]") && stripped.length >= 4)
        {
            auto inner = stripped[2 .. $ - 2];
            auto parts = inner.split(",");
            if (parts.length && parts[0].strip.length)
                attrListPending ~= "#" ~ parts[0].strip;
            advanceLine();
            return;
        }

        if (stripped.startsWith("include::"))
        {
            processInclude(stripped, parent);
            return;
        }

        if (stripped.startsWith("ifdef::") || stripped.startsWith("ifndef::")
            || stripped.startsWith("ifeval::"))
        {
            processConditional(stripped, parent);
            return;
        }

        if (stripped.startsWith("endif::"))
        {
            advanceLine();
            return;
        }

        int sectLevel;
        string sectTitle;
        if (matchSectionTitle(stripped, sectLevel, sectTitle))
        {
            if (sectLevel < 1)
                sectLevel = 1;
            processSection(sectLevel, sectTitle, parent);
            return;
        }

        if (stripped.startsWith("|==="))
        {
            processTable(parent);
            return;
        }

        if (isDelimiter(stripped, '/'))
        {
            skipDelimited('/');
            clearPendingMeta();
            return;
        }

        if (stripped == "--")
        {
            processCompound(parent, "open", "--");
            return;
        }

        if (isDelimiter(stripped, '-'))
        {
            processVerbatim(parent, "listing", stripped);
            return;
        }

        if (isDelimiter(stripped, '.'))
        {
            processVerbatim(parent, "literal", stripped);
            return;
        }

        if (isDelimiter(stripped, '*'))
        {
            processCompound(parent, "sidebar", stripped);
            return;
        }

        if (isDelimiter(stripped, '='))
        {
            auto style = pendingStyle();
            if (isAdmonitionName(style))
                processCompound(parent, "admonition", stripped, style);
            else
                processCompound(parent, "example", stripped);
            return;
        }

        if (isDelimiter(stripped, '_'))
        {
            processCompound(parent, "quote", stripped);
            return;
        }

        if (isDelimiter(stripped, '+'))
        {
            processVerbatim(parent, "pass", stripped);
            return;
        }

        string admonType, admonText;
        if (matchAdmonitionParagraph(stripped, admonType, admonText))
        {
            auto block = new Block();
            block.context = "admonition";
            block.style = admonType;
            applyPendingMeta(block);
            block.lines = [admonText];
            advanceLine();
            while (hasMoreLines() && !peekLine().strip.empty && !isBlockStart(peekLine().strip))
                block.lines ~= advanceLine();
            parent.blocks ~= block;
            return;
        }

        if (stripped.startsWith("image::"))
        {
            processBlockImage(stripped, parent);
            return;
        }

        string term, def;
        int dlevel;
        if (matchDescriptionItem(stripped, term, def, dlevel))
        {
            processDescriptionList(parent);
            return;
        }

        string marker, itemText;
        int mlevel;
        bool ordered, checklist, checked;
        if (matchCalloutListItem(stripped, itemText))
        {
            processColist(parent);
            return;
        }
        if (matchListItem(stripped, marker, itemText, mlevel, ordered, checklist, checked))
        {
            processList(parent, ordered, checklist);
            return;
        }

        processParagraph(parent);
    }

    private void processSection(int level, string title, Block parent)
    {
        advanceLine();
        auto section = new Section(level);
        section.title = title;
        applyPendingMeta(section);

        // [discrete] headings stay flat under the current parent and have no body nest.
        if (section.style == "discrete" || section.roles.canFind("discrete")
            || (("options" in section.attributes)
                && section.attributes["options"].canFind("discrete")))
        {
            section.discrete = true;
            section.style = "discrete";
            parent.blocks ~= section;
            return;
        }

        // Body-level `=` (normalized to level 1 earlier) that isn't the doc title:
        // still a normal section unless marked discrete.
        auto nestParent = findSectionParent(parent, level);
        nestParent.blocks ~= section;

        while (hasMoreLines())
        {
            skipBlankLines();
            if (!hasMoreLines())
                break;
            int nextLevel;
            string nextTitle;
            auto next = peekLine().strip;
            // Pending [discrete] before a heading ends this section's body.
            if (next.startsWith("[") && next.endsWith("]") && !next.startsWith("[["))
            {
                auto style = next[1 .. $ - 1].strip;
                if (style == "discrete" || style.startsWith("discrete")
                    || style.canFind("discrete"))
                {
                    // Look ahead: if next non-empty after attr is a section title, break
                    auto save = currentLine;
                    advanceLine();
                    skipBlankLines();
                    int dl;
                    string dt;
                    bool isDiscreteHeading = hasMoreLines()
                        && matchSectionTitle(peekLine().strip, dl, dt);
                    currentLine = save;
                    if (isDiscreteHeading)
                        break;
                }
            }
            if (matchSectionTitle(next, nextLevel, nextTitle) && nextLevel >= 1
                && nextLevel <= level)
                break;
            parseOneBlock(section);
        }
    }

    private Block findSectionParent(Block root, int level)
    {
        Block current = root;
        while (true)
        {
            if (!current.blocks.length)
                return current;
            auto last = cast(Section) current.blocks[$ - 1];
            if (last is null || last.level >= level)
                return current;
            current = last;
        }
    }

    private void processParagraph(Block parent)
    {
        auto block = new Block();
        block.context = "paragraph";
        applyPendingMeta(block);
        if (block.roles.canFind("lead"))
            block.style = "lead";

        while (hasMoreLines())
        {
            auto s = peekLine().strip;
            if (s.empty || isBlockStart(s))
                break;
            block.lines ~= advanceLine();
        }
        if (!block.lines.length && hasMoreLines())
            block.lines ~= advanceLine();
        if (block.lines.length)
            parent.blocks ~= block;
    }

    private void processVerbatim(Block parent, string context, string open)
    {
        advanceLine();
        auto block = new Block();
        block.context = context;
        applyPendingMeta(block);
        while (hasMoreLines())
        {
            auto s = peekLine().strip;
            if (s == open)
            {
                advanceLine();
                break;
            }
            block.lines ~= advanceLine();
        }
        parent.blocks ~= block;
    }

    private void processCompound(Block parent, string context, string open, string admonStyle = "")
    {
        advanceLine();
        auto block = new Block();
        block.context = context;
        applyPendingMeta(block);
        if (admonStyle.length)
            block.style = admonStyle;
        parent.blocks ~= block;

        while (hasMoreLines())
        {
            auto s = peekLine().strip;
            if (s == open)
            {
                advanceLine();
                break;
            }
            if (s.empty)
            {
                advanceLine();
                continue;
            }
            parseOneBlock(block);
        }
    }

    private void skipDelimited(char ch)
    {
        auto open = advanceLine().strip;
        while (hasMoreLines())
        {
            auto s = peekLine().strip;
            if (s == open)
            {
                advanceLine();
                break;
            }
            advanceLine();
        }
    }

    private void processColist(Block parent)
    {
        auto list = new ListBlock("colist");
        applyPendingMeta(list);
        parent.blocks ~= list;

        while (hasMoreLines())
        {
            if (peekLine().strip.empty)
            {
                auto save = currentLine;
                advanceLine();
                string t;
                if (!(hasMoreLines() && matchCalloutListItem(peekLine().strip, t)))
                {
                    currentLine = save;
                    break;
                }
            }
            string itemText;
            if (!matchCalloutListItem(peekLine().strip, itemText))
                break;
            advanceLine();
            auto item = new ListItem();
            item.text = itemText;
            list.blocks ~= item;
        }
    }

    private void processList(Block parent, bool ordered, bool asChecklist)
    {
        auto list = new ListBlock(ordered ? "olist" : "ulist");
        if (asChecklist)
            list.style = "checklist";
        applyPendingMeta(list);
        parent.blocks ~= list;

        // Stack of open items by marker level (1-based index).
        ListItem[7] levelItem;
        int maxOpen;

        while (hasMoreLines())
        {
            if (peekLine().strip.empty)
            {
                auto save = currentLine;
                advanceLine();
                string m, t;
                int ml;
                bool ord, chk, chked;
                if (!(hasMoreLines() && matchListItem(peekLine().strip, m, t, ml, ord, chk, chked)
                        && ord == ordered))
                {
                    currentLine = save;
                    break;
                }
            }

            string marker, itemText;
            int mlevel;
            bool ord, chk, chked;
            if (!matchListItem(peekLine().strip, marker, itemText, mlevel, ord, chk, chked))
                break;
            if (ord != ordered)
                break;

            advanceLine();
            auto item = new ListItem();
            item.marker = marker;
            item.markerLevel = mlevel;
            item.text = itemText;
            item.checklist = chk || asChecklist;
            item.checked = chked;

            if (mlevel <= 1 || maxOpen == 0)
            {
                list.blocks ~= item;
            }
            else
            {
                auto parentLevel = mlevel - 1;
                while (parentLevel >= 1 && levelItem[parentLevel] is null)
                    parentLevel--;
                if (parentLevel >= 1 && levelItem[parentLevel] !is null)
                    levelItem[parentLevel].blocks ~= item;
                else
                    list.blocks ~= item;
            }

            // Close deeper levels, register this level.
            foreach (i; mlevel + 1 .. maxOpen + 1)
                levelItem[i] = null;
            levelItem[mlevel] = item;
            if (mlevel > maxOpen)
                maxOpen = mlevel;

            while (hasMoreLines())
            {
                auto ns = peekLine();
                if (ns.strip == "+")
                {
                    advanceLine();
                    if (hasMoreLines() && !peekLine().strip.empty)
                    {
                        auto p = new Block();
                        p.context = "paragraph";
                        while (hasMoreLines() && !peekLine().strip.empty
                            && !isBlockStart(peekLine().strip))
                            p.lines ~= advanceLine();
                        item.blocks ~= p;
                    }
                    continue;
                }
                if (ns.startsWith("\t") || ns.startsWith("  "))
                {
                    string m2, t2;
                    int ml2;
                    bool o2, c2, ck2;
                    if (!matchListItem(ns.strip, m2, t2, ml2, o2, c2, ck2))
                    {
                        item.lines ~= advanceLine().stripLeft;
                        continue;
                    }
                }
                break;
            }
        }
    }

    private void processDescriptionList(Block parent)
    {
        auto list = new ListBlock("dlist");
        applyPendingMeta(list);
        parent.blocks ~= list;

        while (hasMoreLines())
        {
            if (peekLine().strip.empty)
            {
                auto save = currentLine;
                advanceLine();
                string t, d;
                int dl;
                if (hasMoreLines() && matchDescriptionItem(peekLine().strip, t, d, dl))
                    continue;
                currentLine = save;
                break;
            }

            string term, def;
            int dlevel;
            if (!matchDescriptionItem(peekLine().strip, term, def, dlevel))
                break;
            advanceLine();

            auto item = new DescriptionListItem();
            item.term = term;
            item.definition = def;
            if (def.empty)
            {
                while (hasMoreLines() && !peekLine().strip.empty)
                {
                    string t2, d2;
                    int dl2;
                    if (matchDescriptionItem(peekLine().strip, t2, d2, dl2)
                        || isBlockStart(peekLine().strip))
                        break;
                    if (item.definition.length)
                        item.definition ~= " ";
                    item.definition ~= advanceLine().strip;
                }
            }
            list.blocks ~= item;
        }
    }

    private void processTable(Block parent)
    {
        advanceLine();
        auto table = new Table();
        applyPendingMeta(table);
        if (auto cols = "cols" in table.attributes)
            table.colsSpec = *cols;
        if (auto opts = "options" in table.attributes)
            if ((*opts).canFind("header"))
                table.hasHeader = true;

        string[] current;

        void flushRow(bool header)
        {
            if (!current.length)
                return;
            auto row = new TableRow();
            row.header = header;
            foreach (c; current)
            {
                auto cell = parseTableCell(c);
                row.cells ~= cell;
            }
            table.rows ~= row;
            current = null;
        }

        bool firstRow = true;
        while (hasMoreLines())
        {
            auto line = peekLine();
            auto s = line.strip;
            if (s.startsWith("|==="))
            {
                advanceLine();
                break;
            }
            if (s.empty)
            {
                advanceLine();
                if (current.length)
                {
                    flushRow(firstRow);
                    firstRow = false;
                }
                continue;
            }
            advanceLine();
            // New cell with style prefix on its own line: a|...
            if (s.length >= 2 && s[1] == '|' && "aeslmh".canFind(s[0]) && current.length)
            {
                current ~= s;
                continue;
            }
            if (!s.startsWith("|") && !(s.length >= 2 && s[1] == '|' && "aeslmh".canFind(s[0]))
                && current.length)
            {
                current[$ - 1] ~= "\n" ~ s;
                continue;
            }
            foreach (cell; splitTableCells(s))
                current ~= cell;
        }
        if (current.length)
            flushRow(firstRow);

        if (table.rows.length)
            table.hasHeader = true;

        parent.blocks ~= table;
    }

    private TableCell parseTableCell(string raw)
    {
        auto cell = new TableCell();
        auto text = raw.strip;
        if (text.length >= 2 && text[1] == '|' && "aeslmh".canFind(text[0]))
        {
            cell.style = text[0 .. 1];
            text = text[2 .. $].strip;
        }
        cell.text = text;
        if (cell.style == "a" && text.length)
        {
            auto nested = new Parser(text, baseDir);
            nested.doc = doc;
            auto holder = new Block();
            holder.context = "open";
            nested.parseInto(doc, holder);
            cell.blocks = holder.blocks;
        }
        return cell;
    }

    private string[] splitTableCells(string line)
    {
        auto s = line;
        // Keep leading style letter: a|foo|b|bar
        if (s.length >= 2 && s[1] == '|' && "aeslmh".canFind(s[0]))
        {
            // first cell includes style prefix; split remaining on |
            auto rest = s[2 .. $];
            string[] cells = [s[0 .. 2] ~ rest.split("|")[0]];
            auto parts = rest.split("|");
            foreach (i, p; parts)
            {
                if (i == 0)
                    continue;
                cells ~= p;
            }
            return cells;
        }
        if (s.startsWith("|"))
            s = s[1 .. $];
        return s.split("|").map!(a => cast(string) a).array;
    }

    private void processBlockImage(string stripped, Block parent)
    {
        auto m = matchFirst(stripped, regex(`^image::([^\[]+)\[([^\]]*)\]`));
        advanceLine();
        if (m.empty)
            return;
        auto block = new Block();
        block.context = "image";
        applyPendingMeta(block);
        block.attributes["target"] = m[1];
        auto parts = m[2].split(",");
        if (parts.length)
            block.attributes["alt"] = parts[0].strip;
        if (parts.length > 1)
            block.attributes["width"] = parts[1].strip;
        if (parts.length > 2)
            block.attributes["height"] = parts[2].strip;
        parent.blocks ~= block;
    }

    private void processInclude(string stripped, Block parent)
    {
        auto m = matchFirst(stripped, regex(`^include::([^\[]+)\[([^\]]*)\]`));
        advanceLine();
        if (m.empty)
            return;
        auto target = m[1];
        auto path = buildNormalizedPath(baseDir, target);
        if (exists(path) && isFile(path))
        {
            auto nested = new Parser(readText(path), dirName(path));
            nested.parseInto(doc, parent);
        }
        else
        {
            auto block = new Block();
            block.context = "paragraph";
            block.lines = ["[include missing: " ~ target ~ "]"];
            parent.blocks ~= block;
        }
    }

    private void processConditional(string stripped, Block parent)
    {
        bool negate = stripped.startsWith("ifndef::");
        bool isIfeval = stripped.startsWith("ifeval::");
        advanceLine();

        bool includeContent = true;
        if (isIfeval)
        {
            // ifeval::["{x}" == "1"] or ifeval::[{n} > 0]
            auto m = matchFirst(stripped, regex(`^ifeval::\[(.*)\]\s*$`));
            if (!m.empty)
                includeContent = evalIfeval(m[1], doc.docAttributes);
            else
                includeContent = false;
        }
        else
        {
            auto m = matchFirst(stripped, regex(`^ifn?def::([^\[]+)\[`));
            if (!m.empty)
            {
                auto names = m[1].split(",");
                bool anyDefined = names.any!(n => (n.strip in doc.docAttributes) !is null);
                includeContent = negate ? !anyDefined : anyDefined;
            }
        }

        auto buf = appender!(string[]);
        int depth = 1;
        while (hasMoreLines())
        {
            auto s = peekLine().strip;
            if (s.startsWith("ifdef::") || s.startsWith("ifndef::") || s.startsWith("ifeval::"))
                depth++;
            if (s.startsWith("endif::"))
            {
                depth--;
                advanceLine();
                if (depth == 0)
                    break;
                continue;
            }
            buf.put(advanceLine());
        }

        if (includeContent)
        {
            auto nested = new Parser(buf.data.join("\n"), baseDir);
            nested.parseInto(doc, parent);
        }
    }

    private void applyPendingMeta(Block block)
    {
        if (blockTitlePending.length)
        {
            block.title = blockTitlePending;
            blockTitlePending = null;
        }
        foreach (raw; attrListPending)
            applyAttrList(block, raw);
        attrListPending = null;
    }

    private void clearPendingMeta()
    {
        attrListPending = null;
        blockTitlePending = null;
    }

    private string pendingStyle()
    {
        foreach (raw; attrListPending)
        {
            auto parts = splitAttrList(raw);
            if (parts.positionals.length)
            {
                auto s = parts.positionals[0];
                s = replaceAll(s, regex(`#[A-Za-z0-9_-]+`), "");
                s = replaceAll(s, regex(`\.[A-Za-z0-9_-]+`), "");
                s = replaceAll(s, regex(`%[A-Za-z0-9_-]+`), "");
                return s.strip;
            }
        }
        return "";
    }

    private void applyAttrList(Block block, string raw)
    {
        auto parsed = splitAttrList(raw);
        foreach (i, pos; parsed.positionals)
        {
            if (i == 0)
                parseStyleShorthand(block, pos);
            else
            {
                block.attributes["positional-" ~ to!string(i)] = pos;
                if (i == 1)
                    block.attributes["language"] = pos;
            }
        }
        foreach (k, v; parsed.named)
            block.attributes[k] = v;
    }

    private void parseStyleShorthand(Block block, string first)
    {
        auto s = first;
        if (auto m = matchFirst(s, regex(`#([A-Za-z0-9_-]+)`)))
        {
            block.id = m[1];
            s = s.replace(m.hit, "");
        }
        while (true)
        {
            auto m = matchFirst(s, regex(`\.([A-Za-z0-9_-]+)`));
            if (m.empty)
                break;
            block.roles ~= m[1];
            s = s.replace(m.hit, "");
        }
        while (true)
        {
            auto m = matchFirst(s, regex(`%([A-Za-z0-9_-]+)`));
            if (m.empty)
                break;
            auto prev = block.attributes.get("options", "");
            block.attributes["options"] = prev.length ? prev ~ "," ~ m[1] : m[1];
            s = s.replace(m.hit, "");
        }
        s = s.strip;
        if (s.length)
            block.style = s;
    }

    private struct AttrListParts
    {
        string[] positionals;
        string[string] named;
    }

    private AttrListParts splitAttrList(string raw)
    {
        AttrListParts result;
        string[] items;
        auto cur = appender!string;
        bool inQuote = false;
        foreach (c; raw)
        {
            if (c == '"')
            {
                inQuote = !inQuote;
                cur.put(c);
            }
            else if (c == ',' && !inQuote)
            {
                items ~= cur.data.strip;
                cur = appender!string;
            }
            else
                cur.put(c);
        }
        if (cur.data.strip.length)
            items ~= cur.data.strip;

        foreach (item; items)
        {
            auto eq = item.indexOf('=');
            if (eq > 0)
            {
                auto key = item[0 .. eq].strip;
                auto val = item[eq + 1 .. $].strip;
                if (val.startsWith("\"") && val.endsWith("\"") && val.length >= 2)
                    val = val[1 .. $ - 1];
                result.named[key] = val;
            }
            else
                result.positionals ~= item;
        }
        return result;
    }

    private bool isBlockTitleLine(string stripped)
    {
        if (stripped.length < 2 || stripped[0] != '.' || stripped[1] == '.' || stripped[1] == ' '
            || stripped[1] == '/')
            return false;
        string m, t;
        int l;
        bool o, c, ch;
        if (matchListItem(stripped, m, t, l, o, c, ch))
            return false;
        int sl;
        string st;
        if (matchSectionTitle(stripped, sl, st))
            return false;
        return true;
    }

    private bool isBlockStart(string stripped)
    {
        if (stripped.empty)
            return true;
        int l;
        string t;
        if (matchSectionTitle(stripped, l, t))
            return true;
        if (stripped.startsWith("[") && stripped.endsWith("]"))
            return true;
        if (stripped.startsWith("include::") || stripped.startsWith("ifdef::")
            || stripped.startsWith("ifndef::") || stripped.startsWith("endif::")
            || stripped.startsWith("ifeval::"))
            return true;
        if (stripped.startsWith("|===") || stripped.startsWith("image::") || stripped == "--"
            || stripped == "'''" || stripped == "<<<")
            return true;
        if (isDelimiter(stripped, '-') || isDelimiter(stripped, '.')
            || isDelimiter(stripped, '*') || isDelimiter(stripped, '=')
            || isDelimiter(stripped, '_') || isDelimiter(stripped, '+')
            || isDelimiter(stripped, '/'))
            return true;
        string a, b;
        if (matchAdmonitionParagraph(stripped, a, b))
            return true;
        string ct;
        if (matchCalloutListItem(stripped, ct))
            return true;
        string m, it;
        int ml;
        bool o, c, ch;
        if (matchListItem(stripped, m, it, ml, o, c, ch))
            return true;
        string term, def;
        int dl;
        if (matchDescriptionItem(stripped, term, def, dl))
            return true;
        if (isBlockTitleLine(stripped))
            return true;
        string an, av;
        if (matchAttrEntry(stripped, an, av))
            return true;
        return false;
    }

    private bool hasMoreLines()
    {
        return currentLine < lines.length;
    }

    private string peekLine()
    {
        if (!hasMoreLines())
            return null;
        return lines[currentLine];
    }

    private string advanceLine()
    {
        if (!hasMoreLines())
            return null;
        return lines[currentLine++];
    }

    private void skipBlankLines()
    {
        while (hasMoreLines() && peekLine().strip.empty)
            advanceLine();
    }
}

bool isDelimiter(string s, char ch)
{
    if (s.length < 4)
        return false;
    foreach (c; s)
        if (c != ch)
            return false;
    return true;
}

bool matchSectionTitle(string line, ref int level, ref string title)
{
    if (!line.length || line[0] != '=')
        return false;
    size_t i = 0;
    while (i < line.length && line[i] == '=')
        i++;
    if (i < 1 || i > 6)
        return false;
    if (i < line.length && line[i] != ' ' && line[i] != '\t')
        return false;
    level = cast(int)(i - 1);
    title = line[i .. $].strip;
    return title.length > 0;
}

bool isAuthorLine(string line)
{
    auto s = line.strip;
    if (s.empty || s.startsWith(":") || s.startsWith("="))
        return false;
    return !matchAttrEntry(s) && !isRevisionLine(s);
}

bool isRevisionLine(string line)
{
    auto s = line.strip;
    return !matchFirst(s, regex(`^v?\d`)).empty;
}

void parseRevisionLine(string line, Document doc)
{
    auto parts = line.split(",");
    if (parts.length)
        doc.revnumber = parts[0].strip;
    if (parts.length > 1)
        doc.revdate = parts[1].strip;
    doc.docAttributes["revnumber"] = doc.revnumber;
    doc.docAttributes["revdate"] = doc.revdate;
}

bool matchAttrEntry(string line, ref string name, ref string value)
{
    auto m = matchFirst(line.strip, regex(`^:([A-Za-z0-9_][A-Za-z0-9_-]*):(?:\s+(.*))?$`));
    if (m.empty)
        return false;
    name = m[1];
    value = m.length > 2 ? m[2] : "";
    return true;
}

bool matchAttrEntry(string line)
{
    string n, v;
    return matchAttrEntry(line, n, v);
}

bool isAdmonitionName(string s)
{
    auto u = s.toUpper;
    return u == "NOTE" || u == "TIP" || u == "IMPORTANT" || u == "WARNING" || u == "CAUTION";
}

bool matchAdmonitionParagraph(string line, ref string admonType, ref string text)
{
    auto m = matchFirst(line, regex(`^(NOTE|TIP|IMPORTANT|WARNING|CAUTION):\s+(.*)$`));
    if (m.empty)
        return false;
    admonType = m[1];
    text = m[2];
    return true;
}

bool matchCalloutListItem(string line, ref string text)
{
    auto m = matchFirst(line, regex(`^<(\d+)>\s+(.*)$`));
    if (m.empty)
        return false;
    text = m[2];
    return true;
}

bool matchListItem(string line, ref string marker, ref string text, ref int level,
    ref bool ordered, ref bool checklist, ref bool checked)
{
    auto u = matchFirst(line, regex(`^(\*{1,5})\s+(.*)$`));
    if (!u.empty)
    {
        marker = u[1];
        level = cast(int) marker.length;
        ordered = false;
        auto rest = u[2];
        auto chk = matchFirst(rest, regex(`^\[([ xX\*])\]\s+(.*)$`));
        if (!chk.empty)
        {
            checklist = true;
            checked = chk[1] != " ";
            text = chk[2];
        }
        else
        {
            checklist = false;
            checked = false;
            text = rest;
        }
        return true;
    }
    auto o = matchFirst(line, regex(`^(\.{1,5})\s+(.*)$`));
    if (!o.empty)
    {
        marker = o[1];
        level = cast(int) marker.length;
        ordered = true;
        checklist = false;
        checked = false;
        text = o[2];
        return true;
    }
    auto n = matchFirst(line, regex(`^(\d+\.)\s+(.*)$`));
    if (!n.empty)
    {
        marker = n[1];
        level = 1;
        ordered = true;
        checklist = false;
        checked = false;
        text = n[2];
        return true;
    }
    return false;
}

bool matchDescriptionItem(string line, ref string term, ref string definition, ref int level)
{
    if (line.strip.startsWith(":"))
        return false;
    auto m = matchFirst(line, regex(`^(.*?)\s*(:{2,4})\s*(.*)$`));
    if (m.empty)
        return false;
    if (m[1].canFind("://") || m[1].empty)
        return false;
    term = m[1].strip;
    level = cast(int) m[2].length - 1;
    definition = m[3].strip;
    return true;
}

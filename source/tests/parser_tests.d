module tests.parser_tests;

import asciidoctor;
import std.algorithm : canFind, startsWith;
import std.stdio;

unittest
{
    auto html = convert("= Title\n\nHello *world*.\n");
    assert(html.canFind("<h1>"), html);
    assert(html.canFind("<strong>world</strong>"), html);
    assert(html.canFind("<!DOCTYPE html>"), html);
}

unittest
{
    ConvertOptions opts;
    opts.standalone = false;
    opts.secure = true;
    auto html = convert("= Title\n\nHello *world*.\n\n++++\n<script>alert(1)</script>\n++++\n", opts);
    assert(!html.canFind("<!DOCTYPE"), html);
    assert(!html.canFind("<html"), html);
    assert(html.canFind("<h1>"), html);
    assert(html.canFind("<strong>world</strong>"), html);
    assert(!html.canFind("<script>"), html);
    assert(html.canFind("&lt;script&gt;"), html);
}

unittest
{
    auto src = q"EOS
= Doc

== Section

* one
* two

. Step
. Step two

NOTE: Be careful.

----
code
----
EOS";
    auto html = convert(src);
    assert(html.canFind("sect1"), html);
    assert(html.canFind("<ul>"), html);
    assert(html.canFind("<ol>"), html);
    assert(html.canFind("admonitionblock"), html);
    assert(html.canFind("listingblock"), html);
    assert(html.canFind("code"), html);
}

unittest
{
    auto src = q"EOS
= T

|===
|A |B

|1 |2
|===
EOS";
    auto html = convert(src);
    assert(html.canFind("<table"), html);
    assert(html.canFind("<th"), html);
}

unittest
{
    auto src = q"EOS
= T
:name: value

Hello {name}.
EOS";
    auto html = convert(src);
    assert(html.canFind("Hello value."), html);
}

unittest
{
    auto src = q"EOS
= T

https://example.com[Example]
link:page.html[Page]
image:photo.png[Alt]
EOS";
    auto html = convert(src);
    assert(html.canFind(`href="https://example.com"`), html);
    assert(html.canFind(`href="page.html"`), html);
    assert(html.canFind(`src="photo.png"`), html);
}

unittest
{
    auto src = q"EOS
= T

* [ ] todo
* [x] done
EOS";
    auto html = convert(src);
    assert(html.canFind("checklist"), html);
}

unittest
{
    auto src = q"EOS
= T

Term:: Definition
EOS";
    auto html = convert(src);
    assert(html.canFind("dlist"), html);
    assert(html.canFind("Term"), html);
    assert(html.canFind("Definition"), html);
}

unittest
{
    auto src = q"EOS
= T

[source,d]
----
void main() {}
----
EOS";
    auto html = convert(src);
    assert(html.canFind("language-d"), html);
}

unittest
{
    auto src = q"EOS
= T
:x:

ifdef::x[]
shown
endif::[]

ifndef::y[]
also
endif::[]
EOS";
    auto html = convert(src);
    assert(html.canFind("shown"), html);
    assert(html.canFind("also"), html);
}

unittest
{
    auto src = q"EOS
= T
:toc:
:toclevels: 2

== One

=== Nested

== Two
EOS";
    auto html = convert(src);
    assert(html.canFind(`id="toc"`), html);
    assert(html.canFind(`href="#one"`), html);
    assert(html.canFind(`href="#two"`), html);
}

unittest
{
    auto src = q"EOS
= T

----
line <1>
----
<1> explanation
EOS";
    auto html = convert(src);
    assert(html.canFind(`class="conum"`), html);
    assert(html.canFind(`class="colist`), html);
    assert(html.canFind("explanation"), html);
}

unittest
{
    auto src = q"EOS
= T
:ver: 2

ifeval::["{ver}" >= "2"]
yes
endif::[]

ifeval::["{ver}" == "1"]
no
endif::[]
EOS";
    auto html = convert(src);
    assert(html.canFind("yes"), html);
    assert(!html.canFind(">no<") && !html.canFind("no</p>"), html);
}

unittest
{
    auto src = q"EOS
= T

[cols="1,2"]
|===
|A |B

|1 |2
|===
EOS";
    auto html = convert(src);
    assert(html.canFind(`<colgroup>`), html);
    assert(html.canFind(`width:33%`), html);
}

unittest
{
    auto src = q"EOS
= T

[discrete]
== Discrete Heading

Normal para.
EOS";
    auto html = convert(src);
    assert(html.canFind(`class="discrete"`), html);
    assert(!html.canFind(`class="sect1"`), html);
}

unittest
{
    auto src = q"EOS
= T

See xref:sec[Section] and <<sec,here>>.
A footnote:[hi] here.

'''
EOS";
    auto html = convert(src);
    assert(html.canFind(`href="#sec"`), html);
    assert(html.canFind(`class="footnote"`), html);
    assert(html.canFind("<hr>"), html);
}

unittest
{
    auto src = q"EOS
= mytool(1)
Author Name
:doctype: manpage
:manpurpose: does useful things

== Synopsis

*mytool* [_options_]

== Description

Hello *world*.
EOS";
    auto man = convert(src, "manpage");
    assert(man.canFind(`.TH "`), man);
    assert(man.canFind("MYTOOL"), man);
    assert(man.canFind(`.SH "NAME"`), man);
    assert(man.canFind(`does useful things`), man);
    assert(man.canFind(`.SH "SYNOPSIS"`) || man.canFind(`.SH "Synopsis"`)
        || man.canFind(`Synopsis`), man);
}

unittest
{
    auto src = "= Report\n\n== Intro\n\nHello *PDF* world.\n\n* one\n* two\n";
    auto pdf = convert(src, "pdf");
    assert(pdf.startsWith("%PDF-1.4"), pdf[0 .. pdf.length < 20 ? pdf.length : 20]);
    assert(pdf.canFind("%%EOF"), pdf);
    assert(pdf.canFind("/Type /Catalog"), pdf);
    assert(pdf.canFind("Hello"), pdf);
    assert(pdf.canFind("Report"), pdf);
}

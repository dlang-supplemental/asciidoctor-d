<div align="center">

<a href="https://github.com/dlang-supplemental/asciidoctor-d/graphs/contributors"><img src="https://img.shields.io/github/contributors/dlang-supplemental/asciidoctor-d.svg?style=for-the-badge" alt="Contributors"></a>
<a href="https://github.com/dlang-supplemental/asciidoctor-d/network/members"><img src="https://img.shields.io/github/forks/dlang-supplemental/asciidoctor-d.svg?style=for-the-badge" alt="Forks"></a>
<a href="https://github.com/dlang-supplemental/asciidoctor-d/stargazers"><img src="https://img.shields.io/github/stars/dlang-supplemental/asciidoctor-d.svg?style=for-the-badge" alt="Stars"></a>
<a href="https://github.com/dlang-supplemental/asciidoctor-d/issues"><img src="https://img.shields.io/github/issues/dlang-supplemental/asciidoctor-d.svg?style=for-the-badge" alt="Issues"></a>

<h3 align="center">Asciidoctor-D</h3>

<p align="center">
Native D implementation of Asciidoctor (AsciiDoc → AST → HTML5).<br>
<a href="https://github.com/dlang-supplemental/asciidoctor-d/issues">Report Bug</a>
·
<a href="https://github.com/dlang-supplemental/asciidoctor-d/issues">Request Feature</a>
</p>

</div>

Fast AsciiDoc processing in D for command-line conversion and editor tooling (LSP tokens, diagnostics, preview).

The feature checklist lives in [`README.adoc`](README.adoc). Changelog: [docs site](https://dlang-supplemental.github.io/docs/asciidoctor-d/changelog/).

## Install

```sdl
dependency "asciidoctor-d" version="~>0.4.0"
```

## Usage

Command line:

```bash
dub build --config=application
./asciidoctor-d input.adoc
./asciidoctor-d -o out.html input.adoc
./asciidoctor-d -b manpage -o prog.1 prog.adoc
./asciidoctor-d -b pdf -o out.pdf input.adoc
```

Library:

```d
import asciidoctor;

auto html = convert(source, "html5", baseDir);

ConvertOptions opts;
opts.standalone = false; // embeddable fragment, no document chrome
opts.secure = true;      // escape raw HTML passthrough
opts.urlFilter = (string url, bool isImage) => url;
html = convert(source, opts);
```

`urlFilter` rewrites a URL before it is written into `href` or `src`. The result has to be `http`, `https`, `mailto`, a fragment, or a relative path. Any other scheme is left out, and the label stays as text.

## Development

```bash
dub build --config=application
dub test
pwsh scripts/run-corpus.ps1
```

## License

MIT

## Contact

DLang Supplemental — dlang@devcentr.org

* Project: https://github.com/dlang-supplemental/asciidoctor-d
* Site: https://dlang-supplemental.github.io

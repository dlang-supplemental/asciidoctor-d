#!/usr/bin/env pwsh
# Fidelity / golden corpus harness for asciidoctor-d.
# Compares structural HTML markers (not full Asciidoctor byte equality).
# Optional: if `asciidoctor` is on PATH, also writes reference HTML for manual diff.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path "$root\asciidoctor-d.exe")) {
  Push-Location $root
  dub build --config=application
  Pop-Location
}

$corpus = Join-Path $root "tests\corpus"
$outDir = Join-Path $root "tests\out"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$cases = Get-ChildItem $corpus -Filter "*.adoc"
if (-not $cases) {
  Write-Error "No corpus files in $corpus"
}

$failed = 0
$passed = 0

foreach ($case in $cases) {
  $name = $case.BaseName
  $htmlOut = Join-Path $outDir "$name.html"
  & "$root\asciidoctor-d.exe" $case.FullName -o $htmlOut
  if ($LASTEXITCODE -ne 0) {
    Write-Host "FAIL $name (converter exit $LASTEXITCODE)"
    $failed++
    continue
  }

  $expectFile = Join-Path $corpus "$name.expect"
  if (Test-Path $expectFile) {
    $html = Get-Content -Raw $htmlOut
    $ok = $true
    foreach ($line in Get-Content $expectFile) {
      $line = $line.Trim()
      if (-not $line -or $line.StartsWith("#")) { continue }
      if ($line.StartsWith("!")) {
        $needle = $line.Substring(1)
        if ($html.Contains($needle)) {
          Write-Host "FAIL $name — unexpected: $needle"
          $ok = $false
        }
      }
      elseif (-not $html.Contains($line)) {
        Write-Host "FAIL $name — missing: $line"
        $ok = $false
      }
    }
    if ($ok) {
      Write-Host "PASS $name"
      $passed++
    }
    else { $failed++ }
  }
  else {
    Write-Host "GEN  $name (no .expect — wrote $htmlOut)"
    $passed++
  }

  if (Get-Command asciidoctor -ErrorAction SilentlyContinue) {
    $ref = Join-Path $outDir "$name.asciidoctor.html"
    & asciidoctor -o $ref $case.FullName
  }
}

Write-Host ""
Write-Host "Corpus: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }

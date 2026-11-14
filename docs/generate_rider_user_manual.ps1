param(
    [string]$SourcePath = (Join-Path $PSScriptRoot 'SC_Courier_Rider_User_Manual.md'),
    [string]$OutputPath = (Join-Path $PSScriptRoot 'SC_Courier_Rider_User_Manual.docx')
)

$ErrorActionPreference = 'Stop'

function Escape-Xml([string]$Value) {
    if ($null -eq $Value) { return '' }
    return [System.Security.SecurityElement]::Escape($Value)
}

function New-Run([string]$Text, [bool]$Bold = $false, [bool]$Code = $false) {
    $escaped = Escape-Xml $Text
    $properties = ''
    if ($Bold -or $Code) {
        $propertyParts = New-Object System.Collections.Generic.List[string]
        if ($Bold) { $propertyParts.Add('<w:b/>') }
        if ($Code) {
            $propertyParts.Add('<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>')
            $propertyParts.Add('<w:color w:val="444444"/>')
            $propertyParts.Add('<w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>')
        }
        $properties = '<w:rPr>' + ($propertyParts -join '') + '</w:rPr>'
    }
    return '<w:r>' + $properties + '<w:t xml:space="preserve">' + $escaped + '</w:t></w:r>'
}

function Convert-Inline([string]$Text) {
    $clean = $Text -replace '\s{2}$', ''
    $matches = [regex]::Matches($clean, '(\*\*.+?\*\*|`.+?`)')
    if ($matches.Count -eq 0) { return New-Run $clean }

    $result = New-Object System.Text.StringBuilder
    $position = 0
    foreach ($match in $matches) {
        if ($match.Index -gt $position) {
            [void]$result.Append((New-Run $clean.Substring($position, $match.Index - $position)))
        }
        $token = $match.Value
        if ($token.StartsWith('**')) {
            [void]$result.Append((New-Run $token.Substring(2, $token.Length - 4) $true $false))
        } else {
            [void]$result.Append((New-Run $token.Substring(1, $token.Length - 2) $false $true))
        }
        $position = $match.Index + $match.Length
    }
    if ($position -lt $clean.Length) {
        [void]$result.Append((New-Run $clean.Substring($position)))
    }
    return $result.ToString()
}

function New-Paragraph(
    [string]$Text,
    [string]$Style = 'Normal',
    [string]$ExtraProperties = ''
) {
    $runs = Convert-Inline $Text
    return '<w:p><w:pPr><w:pStyle w:val="' + $Style + '"/>' + $ExtraProperties + '</w:pPr>' + $runs + '</w:p>'
}

function New-Table([string[][]]$Rows) {
    if ($Rows.Count -eq 0) { return '' }
    $columnCount = ($Rows | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
    if ($columnCount -lt 1) { return '' }
    $cellWidth = [math]::Floor(9360 / $columnCount)

    $xml = New-Object System.Text.StringBuilder
    [void]$xml.Append('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="0" w:type="auto"/><w:tblLayout w:type="autofit"/><w:tblCellMar><w:top w:w="90" w:type="dxa"/><w:left w:w="100" w:type="dxa"/><w:bottom w:w="90" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>')
    for ($column = 0; $column -lt $columnCount; $column++) {
        [void]$xml.Append('<w:gridCol w:w="' + $cellWidth + '"/>')
    }
    [void]$xml.Append('</w:tblGrid>')

    for ($rowIndex = 0; $rowIndex -lt $Rows.Count; $rowIndex++) {
        [void]$xml.Append('<w:tr>')
        for ($column = 0; $column -lt $columnCount; $column++) {
            $value = if ($column -lt $Rows[$rowIndex].Count) { $Rows[$rowIndex][$column] } else { '' }
            $shade = if ($rowIndex -eq 0) { '<w:shd w:val="clear" w:color="auto" w:fill="F97316"/>' } else { '' }
            $cellRuns = Convert-Inline $value
            if ($rowIndex -eq 0) {
                $plainHeader = $value -replace '\*\*', '' -replace '`', ''
                $cellRuns = New-Run $plainHeader $true $false
            }
            [void]$xml.Append('<w:tc><w:tcPr><w:tcW w:w="' + $cellWidth + '" w:type="dxa"/>' + $shade + '</w:tcPr><w:p><w:pPr><w:pStyle w:val="TableText"/></w:pPr>' + $cellRuns + '</w:p></w:tc>')
        }
        [void]$xml.Append('</w:tr>')
    }
    [void]$xml.Append('</w:tbl>')
    return $xml.ToString()
}

function Is-TableSeparator([string]$Line) {
    return $Line -match '^\s*\|?(\s*:?-{3,}:?\s*\|)+\s*$'
}

function Parse-TableRow([string]$Line) {
    $trimmed = $Line.Trim()
    if ($trimmed.StartsWith('|')) { $trimmed = $trimmed.Substring(1) }
    if ($trimmed.EndsWith('|')) { $trimmed = $trimmed.Substring(0, $trimmed.Length - 1) }
    return [string[]]($trimmed.Split('|') | ForEach-Object { $_.Trim() })
}

$lines = Get-Content -LiteralPath $SourcePath -Encoding UTF8
$body = New-Object System.Text.StringBuilder
$index = 0
$seenTitle = $false
$firstSectionBreakInserted = $false

while ($index -lt $lines.Count) {
    $line = $lines[$index]

    if ($line -eq '---') {
        $nextNonBlank = ''
        for ($lookAhead = $index + 1; $lookAhead -lt $lines.Count; $lookAhead++) {
            if (-not [string]::IsNullOrWhiteSpace($lines[$lookAhead])) {
                $nextNonBlank = $lines[$lookAhead]
                break
            }
        }
        if ($nextNonBlank -notmatch '^\*\*End of Rider User Manual') {
            [void]$body.Append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
            $firstSectionBreakInserted = $true
        }
        $index++
        continue
    }

    if ($line -match '^# (.+)$') {
        $heading = $Matches[1]
        if (-not $seenTitle) {
            [void]$body.Append((New-Paragraph $heading 'Title'))
            $seenTitle = $true
        } else {
            $breakBefore = ''
            if (-not $firstSectionBreakInserted -or $heading -match '^(3|5|7|9|12|14|15|18)\.') {
                $breakBefore = '<w:pageBreakBefore/>'
            }
            [void]$body.Append((New-Paragraph $heading 'Heading1' $breakBefore))
            $firstSectionBreakInserted = $false
        }
        $index++
        continue
    }

    if ($line -match '^## (.+)$') {
        $heading = $Matches[1]
        $style = if ($heading -eq 'Rider User Manual') { 'Subtitle' } else { 'Heading2' }
        [void]$body.Append((New-Paragraph $heading $style))
        $index++
        continue
    }

    if ($line -match '^### (.+)$') {
        [void]$body.Append((New-Paragraph $Matches[1] 'Heading3'))
        $index++
        continue
    }

    if ($line.TrimStart().StartsWith('|') -and ($index + 1) -lt $lines.Count -and (Is-TableSeparator $lines[$index + 1])) {
        $rows = New-Object System.Collections.Generic.List[object]
        $rows.Add((Parse-TableRow $line))
        $index += 2
        while ($index -lt $lines.Count -and $lines[$index].TrimStart().StartsWith('|')) {
            $rows.Add((Parse-TableRow $lines[$index]))
            $index++
        }
        [void]$body.Append((New-Table ([string[][]]$rows.ToArray())))
        [void]$body.Append((New-Paragraph '' 'TableSpacing'))
        continue
    }

    if ($line -match '^>\s*(.+)$') {
        $quote = $Matches[1]
        $style = if ($quote -match 'INSERT SCREENSHOT|Suggested file name') { 'ScreenshotPlaceholder' } else { 'Quote' }
        [void]$body.Append((New-Paragraph $quote $style))
        $index++
        continue
    }

    if ($line -match '^\s*-\s+(.+)$') {
        [void]$body.Append((New-Paragraph ('•  ' + $Matches[1]) 'ListParagraph'))
        $index++
        continue
    }

    if ($line -match '^\s*(\d+)\.\s+(.+)$') {
        [void]$body.Append((New-Paragraph ($Matches[1] + '.  ' + $Matches[2]) 'ListParagraph'))
        $index++
        continue
    }

    if ([string]::IsNullOrWhiteSpace($line)) {
        $index++
        continue
    }

    $style = if ($line -match '^\*\*Document version:|^\*\*Application version:|^\*\*Prepared:|^\*\*Audience:') { 'Metadata' } elseif ($line -match '^\*\*End of Rider User Manual') { 'EndNote' } else { 'Normal' }
    [void]$body.Append((New-Paragraph $line $style))
    $index++
}

$documentXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    $($body.ToString())
    <w:sectPr>
      <w:headerReference w:type="default" r:id="rIdHeader"/>
      <w:footerReference w:type="default" r:id="rIdFooter"/>
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="600" w:footer="600" w:gutter="0"/>
      <w:cols w:space="708"/>
      <w:docGrid w:linePitch="360"/>
    </w:sectPr>
  </w:body>
</w:document>
"@

$stylesXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault><w:rPr><w:rFonts w:ascii="Aptos" w:eastAsia="Aptos" w:hAnsi="Aptos" w:cs="Aptos"/><w:sz w:val="21"/><w:szCs w:val="21"/><w:color w:val="262626"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault>
    <w:pPrDefault><w:pPr><w:spacing w:after="140" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="140" w:line="276" w:lineRule="auto"/></w:pPr></w:style>
  <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Subtitle"/><w:qFormat/><w:pPr><w:spacing w:before="1800" w:after="180"/><w:jc w:val="center"/></w:pPr><w:rPr><w:b/><w:color w:val="F97316"/><w:sz w:val="64"/><w:szCs w:val="64"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/><w:next w:val="Metadata"/><w:qFormat/><w:pPr><w:spacing w:after="600"/><w:jc w:val="center"/></w:pPr><w:rPr><w:b/><w:color w:val="444444"/><w:sz w:val="38"/><w:szCs w:val="38"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Metadata"><w:name w:val="Metadata"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="100"/><w:jc w:val="center"/></w:pPr><w:rPr><w:color w:val="666666"/><w:sz w:val="22"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:uiPriority w:val="9"/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="360" w:after="180"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:color w:val="F97316"/><w:sz w:val="36"/><w:szCs w:val="36"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:uiPriority w:val="9"/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="280" w:after="120"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:color w:val="333333"/><w:sz w:val="29"/><w:szCs w:val="29"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="220" w:after="100"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:color w:val="555555"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="420" w:hanging="300"/><w:spacing w:after="70"/></w:pPr></w:style>
  <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="360" w:right="260"/><w:spacing w:before="100" w:after="160"/><w:pBdr><w:left w:val="single" w:sz="22" w:space="10" w:color="F97316"/></w:pBdr><w:shd w:val="clear" w:fill="FFF3E8"/></w:pPr><w:rPr><w:color w:val="633318"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="ScreenshotPlaceholder"><w:name w:val="Screenshot Placeholder"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="70" w:after="70"/><w:ind w:left="200" w:right="200"/><w:jc w:val="center"/><w:pBdr><w:top w:val="dashed" w:sz="10" w:space="8" w:color="F97316"/><w:left w:val="dashed" w:sz="10" w:space="8" w:color="F97316"/><w:bottom w:val="dashed" w:sz="10" w:space="8" w:color="F97316"/><w:right w:val="dashed" w:sz="10" w:space="8" w:color="F97316"/></w:pBdr><w:shd w:val="clear" w:fill="FFF7F0"/></w:pPr><w:rPr><w:b/><w:color w:val="C65300"/><w:sz w:val="20"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="TableText"><w:name w:val="Table Text"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:rPr><w:sz w:val="19"/><w:szCs w:val="19"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="TableSpacing"><w:name w:val="Table Spacing"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="40"/></w:pPr><w:rPr><w:sz w:val="4"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="EndNote"><w:name w:val="End Note"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="400"/><w:jc w:val="center"/></w:pPr><w:rPr><w:b/><w:color w:val="F97316"/></w:rPr></w:style>
  <w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:uiPriority w:val="59"/><w:qFormat/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="70" w:type="dxa"/><w:left w:w="100" w:type="dxa"/><w:bottom w:w="70" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>
</w:styles>
'@

$headerXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="5" w:color="F97316"/></w:pBdr></w:pPr><w:r><w:rPr><w:b/><w:color w:val="666666"/><w:sz w:val="17"/></w:rPr><w:t>SC COURIER  |  RIDER USER MANUAL</w:t></w:r></w:p></w:hdr>
'@

$footerXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:color w:val="777777"/><w:sz w:val="17"/></w:rPr><w:t xml:space="preserve">SC Courier Rider App  •  Version 1.0  •  Page </w:t></w:r><w:fldSimple w:instr="PAGE"><w:r><w:rPr><w:color w:val="777777"/><w:sz w:val="17"/></w:rPr><w:t>1</w:t></w:r></w:fldSimple></w:p></w:ftr>
'@

$contentTypesXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
  <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
  <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>
'@

$rootRelsXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
'@

$documentRelsXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rIdSettings" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
  <Relationship Id="rIdHeader" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>
  <Relationship Id="rIdFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
</Relationships>
'@

$settingsXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:zoom w:percent="100"/><w:updateFields w:val="true"/><w:defaultTabStop w:val="720"/></w:settings>
'@

$timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$coreXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>SC Courier Rider User Manual</dc:title><dc:subject>Rider operating guide</dc:subject><dc:creator>SC Courier</dc:creator><cp:keywords>SC Courier, rider, user manual</cp:keywords><dc:description>User instructions for the SC Courier Rider App.</dc:description><cp:lastModifiedBy>SC Courier</cp:lastModifiedBy><dcterms:created xsi:type="dcterms:W3CDTF">$timestamp</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">$timestamp</dcterms:modified></cp:coreProperties>
"@

$appXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>Microsoft Office Word</Application><AppVersion>16.0000</AppVersion><Company>SC Courier</Company></Properties>
'@

$manualTemp = Join-Path ([System.IO.Path]::GetTempPath()) ('sc-courier-manual-' + [guid]::NewGuid().ToString('N'))
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

try {
    $folders = @(
        $manualTemp,
        (Join-Path $manualTemp '_rels'),
        (Join-Path $manualTemp 'word'),
        (Join-Path $manualTemp 'word\_rels'),
        (Join-Path $manualTemp 'docProps')
    )
    foreach ($folder in $folders) { [void](New-Item -ItemType Directory -Force -Path $folder) }

    [System.IO.File]::WriteAllText((Join-Path $manualTemp '[Content_Types].xml'), $contentTypesXml, $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $manualTemp '_rels\.rels'), $rootRelsXml, $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $manualTemp 'word\document.xml'), $documentXml, $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $manualTemp 'word\styles.xml'), $stylesXml, $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $manualTemp 'word\settings.xml'), $settingsXml, $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $manualTemp 'word\header1.xml'), $headerXml, $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $manualTemp 'word\footer1.xml'), $footerXml, $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $manualTemp 'word\_rels\document.xml.rels'), $documentRelsXml, $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $manualTemp 'docProps\core.xml'), $coreXml, $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $manualTemp 'docProps\app.xml'), $appXml, $utf8NoBom)

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
    if ([System.IO.File]::Exists($resolvedOutput)) { [System.IO.File]::Delete($resolvedOutput) }
    $archive = [System.IO.Compression.ZipFile]::Open($resolvedOutput, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in Get-ChildItem -LiteralPath $manualTemp -Recurse -File) {
            $entryName = $file.FullName.Substring($manualTemp.Length + 1).Replace('\', '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive,
                $file.FullName,
                $entryName,
                [System.IO.Compression.CompressionLevel]::Optimal
            )
        }
    }
    finally {
        $archive.Dispose()
    }
    Write-Output "Created $resolvedOutput"
}
finally {
    if (Test-Path -LiteralPath $manualTemp) {
        Remove-Item -LiteralPath $manualTemp -Recurse -Force
    }
}

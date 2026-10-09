$ErrorActionPreference = 'Stop'
$compiler = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$source = Join-Path $PSScriptRoot 'Trainer.cs'
$output = Join-Path $PSScriptRoot 'Frontiers修改器.exe'
if (Get-Process -Name 'Frontiers修改器' -ErrorAction SilentlyContinue) { throw 'Close the controller before rebuilding.' }
& $compiler /nologo /target:winexe /platform:x64 "/out:$output" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll $source
if ($LASTEXITCODE -ne 0) { throw 'Controller compilation failed.' }

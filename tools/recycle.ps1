# recycle.ps1 - delete files/folders by sending them to the Windows Recycle Bin
# (project rule: never delete permanently; use this script for every removal)
# usage:  powershell -ExecutionPolicy Bypass -File .\tools\recycle.ps1 <path> [<path> ...]
param([Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)][string[]]$Path)
Add-Type -AssemblyName Microsoft.VisualBasic
foreach($p in $Path){
    $full = if([System.IO.Path]::IsPathRooted($p)){ $p } else { Join-Path (Get-Location) $p }
    if(-not (Test-Path -LiteralPath $full)){ Write-Host "skip (not found): $full"; continue }
    $item = Get-Item -LiteralPath $full -Force
    if($item.PSIsContainer){
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($full,'OnlyErrorDialogs','SendToRecycleBin')
        Write-Host "recycled DIR : $full"
    } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($full,'OnlyErrorDialogs','SendToRecycleBin')
        Write-Host "recycled FILE: $full"
    }
}
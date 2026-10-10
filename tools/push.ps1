# push.ps1  -  one-stop push helper for this repository
#
# USAGE
#   A) push to Gitee / any HTTPS remote (prompts for the URL, so no typo risk):
#        powershell -ExecutionPolicy Bypass -File .\tools\push.ps1
#   B) push to GitHub over SSH/443 (works when github.com:443 is blocked but
#      ssh.github.com:443 is reachable):
#        powershell -ExecutionPolicy Bypass -File .\tools\push.ps1 -Ssh
#
# Notes:
#   - It never stores credentials in this repository.
#   - For HTTPS remotes git asks for username + (Personal Access) token / password.
#   - For -Ssh it creates ~/.ssh/id_ed25519 if missing, writes the 443 config for
#     github.com, adds the host key, switches origin to git@github.com and prints
#     the PUBLIC key you must paste into GitHub (Settings -> SSH keys).
param(
    [switch]$Ssh,
    [switch]$Force,
    [string]$Url = ""
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)          # repo root (parent of tools\)
Write-Host "repo root : $PWD"
git rev-parse --is-inside-work-tree | Out-Null
Write-Host ("branch    : " + (git rev-parse --abbrev-ref HEAD))
Write-Host ("commits   : " + (git rev-list --count HEAD))
Write-Host ""

if ($Ssh) {
    # ---------- GitHub over SSH on port 443 ----------
    $sshDir = Join-Path $env:USERPROFILE ".ssh"
    if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }
    $key = Join-Path $sshDir "id_ed25519"
    if (-not (Test-Path $key)) {
        Write-Host "[1/4] generating SSH key (no passphrase) ..."
        cmd /c "ssh-keygen -t ed25519 -N """" -C hdmi2@local -f ""$key"" " | Out-Null
        if (-not (Test-Path $key)) {
            Write-Host "keygen failed - run manually:  ssh-keygen -t ed25519 -C hdmi2@local" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host "[1/4] SSH key already exists: $key"
    }

    $cfg = Join-Path $sshDir "config"
    $block = @"
Host github.com
    HostName ssh.github.com
    Port 443
    User git
    IdentityFile ~/.ssh/id_ed25519
"@
    if (-not (Test-Path $cfg) -or -not (Select-String -Path $cfg -Pattern 'ssh\.github\.com' -Quiet)) {
        Add-Content -Path $cfg -Value $block -Encoding ASCII
        Write-Host "[2/4] wrote 443 mapping into $cfg"
    } else {
        Write-Host "[2/4] $cfg already maps github.com -> ssh.github.com:443"
    }

    Write-Host "[3/4] accepting host key + testing transport ..."
    Write-Host "      (before you add the public key below, 'Permission denied (publickey)' is NORMAL - it only means the transport works)"
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -T git@github.com 2>&1 | ForEach-Object { "      $_" }
    $ErrorActionPreference = $prev

    Write-Host ""
    Write-Host "=== paste this PUBLIC key into GitHub: Settings -> SSH and GPG keys -> New SSH key ==="
    Get-Content "$key.pub"
    Write-Host "=== then re-run this script with -Ssh to push ==="

    git remote remove origin 2>$null
    git remote add origin "git@github.com:Nympha123/HDMI2-EG4S20.git"
    Write-Host ""
    Write-Host "origin -> $(git remote get-url origin)"
    Write-Host ""
    Write-Host "attempting push (succeeds only after the public key above is added to GitHub) ..."
    if ($Force) { git push -u origin main --force } else { git push -u origin main }
} else {
    if ([string]::IsNullOrWhiteSpace($Url)) {
        Write-Host "paste the repository URL (https, e.g. https://gitee.com/yourname/HDMI2-EG4S20.git)"
        $Url = Read-Host "URL"
    }
    $Url = $Url.Trim().TrimEnd('/')
    if ($Url -match '[<>]') { Write-Host "ERROR: URL must not contain angle brackets." -ForegroundColor Red; exit 1 }
    if ($Url -notmatch '\.git$') { $Url = "$Url.git" }

    $name = if ($Url -match 'gitee\.com') { "gitee" } else { "origin" }
    git remote remove $name 2>$null
    git remote add $name $Url
    Write-Host ""
    Write-Host "$name -> $(git remote get-url $name)"
    Write-Host "pushing ..."
    if ($Force) { git push -u $name main --force } else { git push -u $name main }
}
Write-Host ""
Write-Host "done.  local status:"
git status --short
git log --oneline -1

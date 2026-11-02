$voltDir = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $voltDir "voltune.ps1"
$content = Get-Content -Path $scriptPath -Raw

$functionsOnly = $content -replace '(?s)^.*?function Test-IsAdmin', 'function Test-IsAdmin'
$functionsOnly = $functionsOnly -replace '(?s)#\s*\d+\.\s*ENTRYPOINT LOGIC.*', ''

. ([ScriptBlock]::Create($functionsOnly))

$hw = Get-VoltHardwareProfile

# Test Xaml loading
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Extract XAML string from Show-VoltGUI
if ($content -match '(?s)\[xml\]\$xaml\s*=\s*@"(.*?)"@') {
    $rawXaml = $Matches[1]
    # Replace variable placeholders
    $expandedXaml = $ExecutionContext.InvokeCommand.ExpandString($rawXaml)
    [xml]$xmlDoc = $expandedXaml
    $reader = [System.Xml.XmlNodeReader]::new($xmlDoc)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    if ($window) {
        Write-Host "[OK] WPF Window loaded successfully! Title: $($window.Title)" -ForegroundColor Green
        Write-Host "     Controls found: btnGuiAutoOptimize=$([bool]$window.FindName('btnGuiAutoOptimize')), chkHags=$([bool]$window.FindName('chkHags'))" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Failed to instantiate window" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[ERROR] Could not find XAML block in voltune.ps1" -ForegroundColor Red
    exit 1
}

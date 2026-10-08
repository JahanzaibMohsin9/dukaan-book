param(
    [ValidateSet("debug", "profile", "release")]
    [string]$Mode = "release",
    [string]$EnvFile = ".env"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$envPath = Join-Path $repoRoot $EnvFile

if (-not (Test-Path -LiteralPath $envPath)) {
    throw "Missing $EnvFile. Create it from .env.example and add SUPABASE_URL and SUPABASE_ANON_KEY."
}

$requiredKeys = @("SUPABASE_URL", "SUPABASE_ANON_KEY")
$values = @{}

Get-Content -LiteralPath $envPath | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith("#")) {
        return
    }

    $separatorIndex = $line.IndexOf("=")
    if ($separatorIndex -lt 1) {
        return
    }

    $key = $line.Substring(0, $separatorIndex).Trim()
    $value = $line.Substring($separatorIndex + 1).Trim()

    if ($value.Length -ge 2) {
        $first = $value[0]
        $last = $value[$value.Length - 1]
        if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
            $value = $value.Substring(1, $value.Length - 2)
        }
    }

    if ($requiredKeys -contains $key) {
        $values[$key] = $value
    }
}

$missingKeys = $requiredKeys | Where-Object {
    -not $values.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($values[$_])
}

if ($missingKeys.Count -gt 0) {
    throw "Missing required Supabase value(s) in ${EnvFile}: $($missingKeys -join ', ')"
}

$flutterArgs = @("build", "apk", "--$Mode")
foreach ($key in $requiredKeys) {
    $flutterArgs += "--dart-define=$key=$($values[$key])"
}

Push-Location $repoRoot
try {
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
finally {
    Pop-Location
}

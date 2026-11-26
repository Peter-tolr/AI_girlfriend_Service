param(
    [string]$Url = 'http://localhost:5501',
    [int]$TimeoutSeconds = 120,
    [switch]$DryRun
)

# 后台等待后端就绪后再打开浏览器，避免页面打开过早显示"无法连接"
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    try {
        $r = Invoke-WebRequest -Uri "$Url/test" -UseBasicParsing -TimeoutSec 2
        if ($r.StatusCode -eq 200) {
            if ($DryRun) { Write-Output "READY $Url" } else { Start-Process $Url }
            exit 0
        }
    } catch { }
    Start-Sleep -Milliseconds 800
}
if ($DryRun) { Write-Output "TIMEOUT $Url" }
exit 1

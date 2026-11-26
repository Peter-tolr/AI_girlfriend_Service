param(
    [string]$ApiKey,
    [string]$BaseUrl,
    [string]$Model
)

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '   AICompanion  一键配置' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '支持任何 OpenAI 兼容接口：DeepSeek、Kimi、智谱、OpenAI、通义千问、Ollama、中转站……' -ForegroundColor Gray
Write-Host '配置会保存在仓库根目录的 .env 文件中（不会提交到代码仓库）。' -ForegroundColor Gray

if ($ApiKey) {
    # 也支持脚本化调用：setup.ps1 -ApiKey sk-xxx [-BaseUrl https://api.deepseek.com -Model deepseek-chat]
    $map = Import-DotEnv
    $targetBaseUrl = $BaseUrl
    if (-not $targetBaseUrl) { $targetBaseUrl = $map['AI_BASE_URL'] }
    if (-not $targetBaseUrl) { $targetBaseUrl = $script:DefaultBaseUrl }
    $targetModel = $Model
    if (-not $targetModel) { $targetModel = $map['AI_MODEL'] }
    if (-not $targetModel) { $targetModel = $script:DefaultModel }

    Write-Info "校验地址：$targetBaseUrl"
    Write-Info "使用模型：$targetModel"
    $result = Test-AiEndpoint $targetBaseUrl $ApiKey $targetModel
    if ($result.Status -eq 'invalid') {
        Write-Warn2 '鉴权失败（401/403）：Key 和该地址不匹配，未保存。'
        exit 1
    }
    if ($result.Status -eq 'badmodel') {
        Write-Warn2 "接口拒绝了请求（400）：请检查模型名。返回：$($result.Message)"
        exit 1
    }
    if ($result.Status -eq 'valid') { Write-Ok '校验通过。' }
    else { Write-Warn2 "暂时无法在线校验（$($result.Message)），先保存。" }
    Save-AiConfig $targetBaseUrl $ApiKey $targetModel
    Write-Ok "已保存到 $script:EnvFile"
} else {
    $key = Invoke-SetupPrompt
    if ($null -eq $key) {
        Write-Host ''
        Write-Warn2 '未完成配置。'
        exit 1
    }
}

Write-Host ''
Write-Ok '配置完成，现在双击「一键启动.bat」即可启动服务。'
Write-Host ''

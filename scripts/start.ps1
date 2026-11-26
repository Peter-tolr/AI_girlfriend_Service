param(
    [string]$ApiKey,
    [string]$BaseUrl,
    [string]$Model,
    [string]$JavaHome,
    [switch]$NoBrowser,
    [switch]$Rebuild,
    [switch]$SkipBuild
)

. (Join-Path $PSScriptRoot 'common.ps1')

function Fail([string]$Message) {
    Write-Host ''
    Write-Host "× $Message" -ForegroundColor Red
    exit 1
}

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '   AICompanion  一键启动' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

# 1. 模型接口配置（没配就现场配置）
Write-Step '检查模型接口配置'
$key = Ensure-AiConfig $ApiKey $BaseUrl $Model
if ($null -eq $key) { Fail '没有可用的 API Key，已取消启动。' }
$endpoint = Resolve-AiEndpoint $env:AI_BASE_URL
Write-Ok "接口地址：$($endpoint.BaseUrl)$($endpoint.ChatPath)"
Write-Ok "使用模型：$env:AI_MODEL"
Write-Info '人设：companion_skill/（改完重启即可生效，不用重新打包）'

# 2. 端口检查：已经在跑就不重复启动
Write-Step '检查端口 5501'
if (Test-AppReady) {
    Write-Ok '服务已经在运行，直接打开页面'
    if (-not $NoBrowser) { Start-Process $script:AppUrl }
    Write-Info "地址：$script:AppUrl"
    Write-Info '如需重启，请先关闭正在运行的服务窗口。'
    exit 0
}
$owner = Get-PortOwner 5501
if ($owner) { Fail "端口 5501 被其他进程占用（PID $owner），请先关闭它再试。" }
Write-Ok '端口可用'

# 3. JDK
Write-Step '查找 JDK（需要 17 及以上）'
$jdk = Find-Jdk $JavaHome
if (-not $jdk) {
    Write-Warn2 '没有找到 JDK 17+。'
    Write-Info '可以任选一种方式解决：'
    Write-Info '  1) 安装：winget install EclipseAdoptium.Temurin.21.JDK'
    Write-Info '  2) 如果已经装好，设置环境变量 JAVA_HOME 后重试'
    Write-Info '  3) 也可以双击 .bat 时带参数：-JavaHome "C:\path\to\jdk"'
    Fail '缺少 JDK'
}
$env:JAVA_HOME = $jdk
Write-Ok "使用 JDK：$jdk"

# 4. 构建（jar 不存在、源码有改动或强制重建时才执行）
$jar = Join-Path $script:RepoRoot 'springai-server\target\springai-server.jar'
$needBuild = $false
if ($Rebuild -or -not (Test-Path $jar)) { $needBuild = $true }

if (-not $needBuild -and -not $SkipBuild) {
    $jarTime = (Get-Item $jar).LastWriteTimeUtc
    $newerPom = @(
        (Join-Path $script:RepoRoot 'pom.xml'),
        (Join-Path $script:RepoRoot 'springai-server\pom.xml')
    ) | Where-Object { (Test-Path $_) -and ((Get-Item $_).LastWriteTimeUtc -gt $jarTime) } | Select-Object -First 1
    $newerSrc = Get-ChildItem (Join-Path $script:RepoRoot 'springai-server\src') -Recurse -File |
        Where-Object { $_.LastWriteTimeUtc -gt $jarTime } | Select-Object -First 1
    # 人设文件也会打进 jar，改过同样要重建
    $newerPersona = Get-ChildItem (Join-Path $script:RepoRoot 'companion_skill') -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -gt $jarTime } | Select-Object -First 1
    if ($newerPom -or $newerSrc -or $newerPersona) { $needBuild = $true }
}

if ($needBuild -and -not $SkipBuild) {
    Write-Step '构建后端'
    Write-Info '首次运行会自动下载 Maven 和项目依赖，可能需要几分钟，请耐心等待...'

    $staticIndex = Join-Path $script:RepoRoot 'springai-server\src\main\resources\static\index.html'
    if (-not (Test-Path $staticIndex)) {
        Write-Warn2 '静态前端产物缺失，jar 里将没有页面（只提供 API）。'
        Write-Warn2 '如需页面：在有 Node 的环境执行 cd springai-web && npm run build'
    }

    $mvnw = Join-Path $script:RepoRoot 'mvnw.cmd'
    if (-not (Test-Path $mvnw)) { Fail '缺少 mvnw.cmd，仓库不完整。' }

    $code = 1
    # PowerShell 5.1 会把原生命令的 stderr 当成终止错误（$ErrorActionPreference='Stop' 时），
    # 这里临时放宽，避免 Maven 的警告直接把脚本打断
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $script:RepoRoot
    try {
        & $mvnw -B -ntp '-DskipTests' package
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
        $ErrorActionPreference = $oldEap
    }
    if ($code -ne 0) { Fail "构建失败（退出码 $code），请查看上面的 Maven 输出。" }
    if (-not (Test-Path $jar)) { Fail '构建结束但没有找到 jar 文件。' }
    Write-Ok '构建完成'
} else {
    Write-Info '已有可用的 jar，跳过构建（加 -Rebuild 可强制重建）'
}

# 5. 后台等待就绪再打开浏览器
if (-not $NoBrowser) {
    $browserScript = Join-Path $PSScriptRoot 'open-browser.ps1'
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $browserScript, '-Url', $script:AppUrl
    ) -WindowStyle Hidden | Out-Null
}

# 6. 前台启动，日志直接显示在本窗口；Ctrl+C 或关窗口即停止
Write-Step "启动服务：$script:AppUrl"
Write-Info '浏览器会自动打开；按 Ctrl+C 或关闭本窗口即可停止服务'
Write-Host ''

Push-Location $script:RepoRoot
$oldEap = $ErrorActionPreference
try {
    # 不要写成裸的 -Dfile.encoding=UTF-8：PowerShell 5.1 会在点号处把参数拆成两段，
    # Java 会把它当成主类名而报 ClassNotFoundException。JDK 18+ 默认就是 UTF-8，无需该参数。
    $ErrorActionPreference = 'Continue'
    & (Join-Path $jdk 'bin\java.exe') -jar $jar
} finally {
    $ErrorActionPreference = $oldEap
    Pop-Location
    Write-Host ''
    Write-Info '服务已停止。'
}

# 正常停止（含 Ctrl+C）都返回 0，避免 .bat 误报"启动失败"
exit 0

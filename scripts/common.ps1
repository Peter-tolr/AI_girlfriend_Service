# 公共函数库：被 setup.ps1 / start.ps1 点源引用。
# 注意：本文件必须保存为 UTF-8 带 BOM，否则 PowerShell 5.1 会把中文读成乱码。

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:EnvFile = Join-Path $script:RepoRoot '.env'
$script:AppUrl = 'http://localhost:5501'
$script:DefaultBaseUrl = 'https://dashscope.aliyuncs.com/compatible-mode'
$script:DefaultModel = 'qwen-plus'

# 常见服务商预设：对话接口都兼容 OpenAI 协议，换一家只要换这三个值
$script:Providers = @(
    @{ Key = '1'; Name = '阿里云百炼（通义千问）'; BaseUrl = 'https://dashscope.aliyuncs.com/compatible-mode'; Model = 'qwen-plus' },
    @{ Key = '2'; Name = 'DeepSeek';            BaseUrl = 'https://api.deepseek.com'; Model = 'deepseek-chat' },
    @{ Key = '3'; Name = 'Kimi（月之暗面）';      BaseUrl = 'https://api.moonshot.cn/v1'; Model = 'moonshot-v1-8k' },
    @{ Key = '4'; Name = '智谱 GLM';             BaseUrl = 'https://open.bigmodel.cn/api/paas/v4'; Model = 'glm-4-flash' },
    @{ Key = '5'; Name = 'OpenAI';              BaseUrl = 'https://api.openai.com'; Model = 'gpt-4o-mini' },
    @{ Key = '6'; Name = '本地 Ollama';          BaseUrl = 'http://localhost:11434/v1'; Model = 'qwen2.5:7b' }
)

function Write-Step([string]$Text) { Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Info([string]$Text) { Write-Host "    $Text" -ForegroundColor Gray }
function Write-Ok([string]$Text) { Write-Host "    $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text) { Write-Host "    $Text" -ForegroundColor Yellow }

# 读取仓库根目录的 .env（KEY=VALUE 格式，忽略注释和空行）
function Read-DotEnv {
    $map = @{}
    if (Test-Path $script:EnvFile) {
        $lines = [System.IO.File]::ReadAllLines($script:EnvFile, [System.Text.Encoding]::UTF8)
        foreach ($line in $lines) {
            $t = $line.Trim()
            if (-not $t -or $t.StartsWith('#')) { continue }
            $i = $t.IndexOf('=')
            if ($i -gt 0) {
                $k = $t.Substring(0, $i).Trim()
                $v = $t.Substring($i + 1).Trim().Trim('"').Trim("'")
                if ($k) { $map[$k] = $v }
            }
        }
    }
    return $map
}

# 把 .env 里的配置导入当前进程，java 启动时直接继承
function Import-DotEnv {
    $map = Read-DotEnv
    foreach ($k in $map.Keys) {
        Set-Item -Path "Env:$k" -Value $map[$k]
    }
    return $map
}

# 保存配置。注释保持 ASCII，避免用记事本打开时因编码猜测出现乱码
function Save-AiConfig([string]$BaseUrl, [string]$Key, [string]$Model) {
    $lines = @(
        '# local config, ignored by git, do not commit',
        "AI_BASE_URL=$BaseUrl",
        "AI_API_KEY=$Key",
        "AI_MODEL=$Model"
    )
    # 百炼的 Key 同时给文生图用，其他服务商的 Key 对文生图无效，不写入
    if ($BaseUrl -like '*dashscope.aliyuncs.com*' -and $Key) {
        $lines += "DASHSCOPE_API_KEY=$Key"
    }
    [System.IO.File]::WriteAllText($script:EnvFile, (($lines -join "`r`n") + "`r`n"),
        (New-Object System.Text.UTF8Encoding($false)))
}

function ConvertFrom-SecureStringPlain([Security.SecureString]$Secure) {
    if (-not $Secure) { return '' }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# 把用户填的地址拆成「服务根地址 + 接口路径」。
# 规则和 Java 端 AiEnvironmentPostProcessor 保持一致：
#   https://api.deepseek.com                      -> base=原样,              path=/v1/chat/completions
#   https://api.moonshot.cn/v1                    -> base=...,  path=/v1/chat/completions
#   https://open.bigmodel.cn/api/paas/v4          -> base=.../paas, path=/v4/chat/completions
#   https://host/v1/chat/completions（用户直接粘完整地址）-> base=https://host, path=/v1/chat/completions
function Resolve-AiEndpoint([string]$BaseUrl) {
    $url = "$BaseUrl".Trim()
    while ($url.EndsWith('/')) { $url = $url.Substring(0, $url.Length - 1) }
    if (-not $url) { $url = $script:DefaultBaseUrl }

    if ($url.EndsWith('/chat/completions')) {
        $prefix = $url.Substring(0, $url.Length - '/chat/completions'.Length)
        if ($prefix -match '^(?<base>.+)/(?<ver>v\d+[A-Za-z0-9.\-]*)$') {
            return @{ BaseUrl = $matches['base']; ChatPath = "/$($matches['ver'])/chat/completions" }
        }
        return @{ BaseUrl = $prefix; ChatPath = '/chat/completions' }
    }
    if ($url -match '^(?<base>.+)/(?<ver>v\d+[A-Za-z0-9.\-]*)$') {
        return @{ BaseUrl = $matches['base']; ChatPath = "/$($matches['ver'])/chat/completions" }
    }
    return @{ BaseUrl = $url; ChatPath = '/v1/chat/completions' }
}

# 在线校验：发一条 1 token 的对话请求。
# 返回 @{ Status = 'valid' | 'invalid' | 'badmodel' | 'notfound' | 'unknown'; Message = '...' }
function Test-AiEndpoint([string]$BaseUrl, [string]$Key, [string]$Model) {
    $endpoint = Resolve-AiEndpoint $BaseUrl
    $uri = "$($endpoint.BaseUrl)$($endpoint.ChatPath)"
    if (-not $Model) { $Model = $script:DefaultModel }

    $body = @{
        model      = $Model
        messages   = @(@{ role = 'user'; content = 'hi' })
        max_tokens = 1
        stream     = $false
    } | ConvertTo-Json -Depth 5

    $headers = @{}
    if ($Key) { $headers['Authorization'] = "Bearer $Key" }

    try {
        $null = Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' `
            -Headers $headers -Body $body -TimeoutSec 25
        return @{ Status = 'valid'; Message = '' }
    } catch {
        $resp = $_.Exception.Response
        $detail = ''
        try {
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
        } catch { }
        if (-not $detail -and $resp) {
            # Windows PowerShell 5.1 有时不会填充 ErrorDetails，只能自己读响应流
            try {
                $stream = $resp.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $detail = $reader.ReadToEnd()
                }
            } catch { }
        }
        if ($detail) {
            try {
                $json = $detail | ConvertFrom-Json
                if ($json.error -and $json.error.message) { $detail = $json.error.message }
                elseif ($json.message) { $detail = $json.message }
            } catch { }
        }
        if ($resp) {
            $code = [int]$resp.StatusCode
            if ($code -eq 401 -or $code -eq 403) { return @{ Status = 'invalid'; Message = $detail } }
            if ($code -eq 404) { return @{ Status = 'notfound'; Message = $uri } }
            if ($code -eq 400) { return @{ Status = 'badmodel'; Message = $detail } }
            return @{ Status = 'unknown'; Message = "HTTP $code $detail" }
        }
        return @{ Status = 'unknown'; Message = $_.Exception.Message }
    }
}

# 交互式配置：选服务商、填 Key、校验、保存
function Invoke-SetupPrompt {
    $map = Import-DotEnv
    $currentBase = $map['AI_BASE_URL']
    $currentKey = $map['AI_API_KEY']
    if (-not $currentKey) { $currentKey = $map['DASHSCOPE_API_KEY'] }
    $currentModel = $map['AI_MODEL']

    if ($currentBase -and $currentKey) {
        $masked = $currentKey
        if ($currentKey.Length -gt 10) { $masked = $currentKey.Substring(0, 6) + '****' + $currentKey.Substring($currentKey.Length - 4) }
        Write-Info "当前配置：$currentBase"
        Write-Info "           模型 $currentModel，Key $masked"
    }

    $baseUrl = $script:DefaultBaseUrl
    $model = $script:DefaultModel

    Write-Host ''
    Write-Host '请选择要使用的大模型服务（都走 OpenAI 兼容协议）：'
    foreach ($p in $script:Providers) {
        Write-Host ("  {0}) {1,-22} {2}" -f $p.Key, $p.Name, $p.BaseUrl) -ForegroundColor Gray
    }
    Write-Host '  7) 自定义（自己填地址和模型名）' -ForegroundColor Gray
    Write-Host '直接回车 = 保持现有配置' -ForegroundColor Gray

    while ($true) {
        $choice = (Read-Host '序号').Trim()
        if (-not $choice) {
            if ($currentBase -and $currentKey) { return $currentKey }
            $choice = '1'
        }
        if ($choice -eq '7') {
            $input = (Read-Host '接口地址 BASE_URL（例如 https://api.deepseek.com 或 https://api.moonshot.cn/v1）').Trim()
            if (-not $input) { Write-Warn2 '地址不能为空，请重新选择。'; continue }
            $baseUrl = $input
            $input = (Read-Host '模型名（例如 deepseek-chat）').Trim()
            if ($input) { $model = $input } else { $model = $script:DefaultModel }
            break
        }
        $hit = $script:Providers | Where-Object { $_.Key -eq $choice } | Select-Object -First 1
        if ($hit) {
            $baseUrl = $hit.BaseUrl
            $model = $hit.Model
            break
        }
        Write-Warn2 '没有这个序号，请重新输入。'
    }

    # 已经有同地址的 Key 时，直接回车就沿用
    $reuse = $null
    if ($currentKey -and $currentBase -and
        (Resolve-AiEndpoint $currentBase).BaseUrl -eq (Resolve-AiEndpoint $baseUrl).BaseUrl) {
        $reuse = $currentKey
    }
    if ($reuse) {
        Write-Info "检测到该地址已保存过 Key，直接回车即可沿用。"
    }

    $saved = $false
    while (-not $saved) {
        $secure = Read-Host 'API Key（输入内容不会显示，直接回车保留现有配置）' -AsSecureString
        $key = (ConvertFrom-SecureStringPlain $secure).Trim()
        if (-not $key) { $key = $reuse }
        if (-not $key) {
            # Ollama 这类本地服务不需要 Key
            if ($baseUrl -match '^https?://(localhost|127\.0\.0\.1)') {
                Write-Info '本地服务，未填 Key，按无鉴权方式调用。'
                $key = ''
                break
            }
            Write-Warn2 '没有输入 Key，已取消。'
            return $null
        }
        Write-Info "正在校验：$baseUrl  模型 $model ..."
        $result = Test-AiEndpoint $baseUrl $key $model
        if ($result.Status -eq 'valid') {
            Write-Ok '校验通过。'
            $saved = $true
        } elseif ($result.Status -eq 'invalid') {
            Write-Warn2 '鉴权失败（401/403）：Key 和这个地址不匹配，请重新输入。'
        } elseif ($result.Status -eq 'badmodel') {
            Write-Warn2 "接口拒绝了请求（400）：多半是模型名不对。返回：$($result.Message)"
            $newModel = (Read-Host "换一个模型名（直接回车保持 $model）").Trim()
            if ($newModel) { $model = $newModel }
        } elseif ($result.Status -eq 'notfound') {
            Write-Warn2 "地址不存在（404）：$($result.Message)"
        } else {
            Write-Warn2 "暂时无法在线校验（$($result.Message)），先保存，启动后可在页面上验证。"
            $saved = $true
        }
    }

    Save-AiConfig $baseUrl $key $model
    $env:AI_BASE_URL = $baseUrl
    $env:AI_API_KEY = $key
    $env:AI_MODEL = $model
    if ($baseUrl -like '*dashscope.aliyuncs.com*') { $env:DASHSCOPE_API_KEY = $key }
    Write-Ok "已保存到 $script:EnvFile"
    return $key
}

# 优先用参数，其次 .env，再次当前进程环境变量；都没有则现场配置
function Ensure-AiConfig([string]$ApiKeyOverride, [string]$BaseUrlOverride, [string]$ModelOverride) {
    $map = Import-DotEnv
    if ($BaseUrlOverride) { $env:AI_BASE_URL = $BaseUrlOverride }
    if ($ModelOverride) { $env:AI_MODEL = $ModelOverride }
    if ($ApiKeyOverride) { $env:AI_API_KEY = $ApiKeyOverride }

    if (-not $env:AI_BASE_URL) { $env:AI_BASE_URL = $script:DefaultBaseUrl }
    if (-not $env:AI_MODEL) { $env:AI_MODEL = $script:DefaultModel }

    $key = $env:AI_API_KEY
    if (-not $key -or $key -eq 'not-configured') { $key = $env:DASHSCOPE_API_KEY }
    $localOnly = $env:AI_BASE_URL -match '^https?://(localhost|127\.0\.0\.1)'

    if (-not $key -and -not $localOnly) {
        Write-Warn2 '还没有配置 API Key，先来配置一下。'
        $key = Invoke-SetupPrompt
        if (-not $key) { return $null }
    }
    if ($key -and $key -ne 'not-configured') {
        $env:AI_API_KEY = $key
        if ($env:AI_BASE_URL -like '*dashscope.aliyuncs.com*') { $env:DASHSCOPE_API_KEY = $key }
    }
    return $key
}

# 探测 JDK 主版本号。
# 优先读 JDK 自带的 release 文件：不启动进程，也不会踩 PowerShell 5.1 把
# 原生命令 stderr 当成终止错误的坑（$ErrorActionPreference='Stop' 时 java -version 会直接抛异常）。
function Get-JavaMajor([string]$JdkRoot) {
    $release = Join-Path $JdkRoot 'release'
    if (Test-Path $release) {
        try {
            $line = Get-Content $release -ErrorAction Stop |
                Where-Object { $_ -match '^JAVA_VERSION=' } |
                Select-Object -First 1
            if ($line) {
                $v = $line.Substring($line.IndexOf('=') + 1).Trim().Trim('"')
                $parts = $v.Split('.')
                $major = [int]$parts[0]
                if ($major -eq 1 -and $parts.Count -gt 1) { $major = [int]$parts[1] }
                return $major
            }
        } catch { }
    }
    return (Get-JavaMajorFromCommand (Join-Path $JdkRoot 'bin\java.exe'))
}

# release 文件不存在时的兜底：通过 cmd 合并 stdout/stderr 读取版本
function Get-JavaMajorFromCommand([string]$JavaExe) {
    if (-not (Test-Path $JavaExe)) { return 0 }
    try {
        $out = & cmd.exe /c "`"$JavaExe`" -version 2>&1" | Out-String
        $m = [regex]::Match($out, 'version\s+"(\d+)')
        if ($m.Success) { return [int]$m.Groups[1].Value }
    } catch { }
    return 0
}

# 查找 JDK（必须带 javac、且版本 >= 17），返回 JDK 根目录
function Find-Jdk([string]$Preferred) {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Preferred) { $candidates.Add((Join-Path $Preferred 'bin\javac.exe')) }
    if ($env:JAVA_HOME) { $candidates.Add((Join-Path $env:JAVA_HOME 'bin\javac.exe')) }
    $cmd = Get-Command javac.exe -ErrorAction SilentlyContinue
    if ($cmd) { $candidates.Add($cmd.Source) }

    $patterns = @(
        "$env:ProgramFiles\Java\*\bin\javac.exe",
        "$env:ProgramFiles\Eclipse Adoptium\*\bin\javac.exe",
        "$env:ProgramFiles\Microsoft\jdk-*\bin\javac.exe",
        "$env:ProgramFiles\JetBrains\*\jbr\bin\javac.exe",
        "$env:LOCALAPPDATA\Programs\JetBrains\*\jbr\bin\javac.exe",
        "$env:USERPROFILE\.jdks\*\bin\javac.exe",
        "D:\*PyCharm*\jbr\bin\javac.exe",
        "D:\*IntelliJ*\jbr\bin\javac.exe",
        "D:\*JetBrains*\*\jbr\bin\javac.exe",
        "C:\*PyCharm*\jbr\bin\javac.exe",
        "C:\*IntelliJ*\jbr\bin\javac.exe"
    )
    foreach ($p in $patterns) {
        foreach ($f in (Get-Item $p -ErrorAction SilentlyContinue)) { $candidates.Add($f.FullName) }
    }

    foreach ($javac in $candidates) {
        if (-not $javac -or -not (Test-Path $javac)) { continue }
        $jdkRoot = Split-Path (Split-Path $javac -Parent) -Parent
        $major = Get-JavaMajor $jdkRoot
        if ($major -ge 17) { return $jdkRoot }
    }
    return $null
}

function Test-AppReady {
    try {
        $r = Invoke-WebRequest -Uri "$script:AppUrl/test" -UseBasicParsing -TimeoutSec 2
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Get-PortOwner([int]$Port) {
    try {
        $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop | Select-Object -First 1
        return $c.OwningProcess
    } catch { return $null }
}

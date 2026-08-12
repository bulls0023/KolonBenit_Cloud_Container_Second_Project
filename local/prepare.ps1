<#
.SYNOPSIS
    로컬 통합 검증 준비. digest 해석 + mysql-init 생성 + .env 발급.

.DESCRIPTION
    Hybrid Toy Project - local/prepare.ps1

    이 스크립트가 하는 일
      1. amazoncorretto:25-alpine 의 실제 digest 를 조회해 Dockerfile 에 반영
         (구축설명서 §3.3-3 의 수작업을 대체한다. README §21 digest 표에도 기록할 값이다)
      2. db/01~04.sql 의 자리표시자를 치환해 local/mysql-init/ 에 배치
      3. 로컬 전용 비밀번호를 무작위 생성해 .env 로 발급

    산출물은 전부 .gitignore 대상이다. 커밋되지 않는다.

.PARAMETER Force
    mysql-init 과 .env 가 이미 있어도 다시 만든다.

.EXAMPLE
    cd local
    .\prepare.ps1
#>

[CmdletBinding()]
param(
    [switch] $Force,

    # 기본값은 표준 리포 구조(repo/local, repo/db, repo/apps/was)를 가정한다.
    # 다른 배치라면 명시적으로 넘긴다.
    #   .\prepare.ps1 -DbDir C:\choiseobin\db -WasDir C:\choiseobin\was
    [string] $DbDir,
    [string] $WasDir,
    [string] $BffDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BASE_IMAGE   = 'amazoncorretto:25-alpine'
$HTPASSWD_IMG = 'httpd:2.4-alpine'
$LOCAL_STAFF_PASSWORD = 'Local!Hospital2026'   # 로컬 전용. 운영과 무관하다.

$root     = Split-Path -Parent $PSScriptRoot
$initDir  = Join-Path $PSScriptRoot 'mysql-init'
$envFile  = Join-Path $PSScriptRoot '.env'

# ---------------------------------------------------------------------
# 경로 확정 - 어긋난 배치를 조용히 통과시키지 않는다
# ---------------------------------------------------------------------
function Resolve-Dir {
    param([string] $Explicit, [string[]] $Candidates, [string] $Marker, [string] $Label)

    if ($Explicit) {
        if (Test-Path (Join-Path $Explicit $Marker)) { return (Resolve-Path $Explicit).Path }
        Write-Host "[ERROR] -$Label 로 지정한 경로에 $Marker 가 없다: $Explicit" -ForegroundColor Red
        exit 1
    }
    foreach ($c in $Candidates) {
        if (Test-Path (Join-Path $c $Marker)) { return (Resolve-Path $c).Path }
    }

    Write-Host ''
    Write-Host "[ERROR] $Label 디렉토리를 찾지 못했다 ($Marker 기준)." -ForegroundColor Red
    Write-Host '        탐색한 경로:'
    $Candidates | ForEach-Object { Write-Host "          $_" }
    Write-Host ''
    Write-Host '        기대 구조:' -ForegroundColor Yellow
    Write-Host '          repo/'
    Write-Host '            db/        01_schema.sql ~ 04_icd_seed.sql'
    Write-Host '            apps/was/  build.gradle.kts, Dockerfile, src/'
    Write-Host '            local/     이 스크립트'
    Write-Host ''
    Write-Host '        구조가 다르면 직접 지정한다:' -ForegroundColor Yellow
    Write-Host '          .\prepare.ps1 -DbDir <경로> -WasDir <경로>'
    Write-Host ''
    exit 1
}

$dbDir = Resolve-Dir -Explicit $DbDir -Label 'DbDir' -Marker '01_schema.sql' -Candidates @(
    (Join-Path $root 'db'),
    (Join-Path $PSScriptRoot '..\db'),
    (Join-Path $root '..\db')
)

$wasDir = Resolve-Dir -Explicit $WasDir -Label 'WasDir' -Marker 'build.gradle.kts' -Candidates @(
    (Join-Path $root 'apps\was'),
    (Join-Path $root 'was'),
    (Join-Path $root '..\was')
)

$bffDir = Resolve-Dir -Explicit $BffDir -Label 'BffDir' -Marker 'build.gradle.kts' -Candidates @(
    (Join-Path $root 'apps\\bff'),
    (Join-Path $root 'bff'),
    (Join-Path $root '..\\bff')
)

# digest 치환 대상. 두 Dockerfile 이 같은 베이스를 쓴다.
$dockerfiles = @((Join-Path $wasDir 'Dockerfile'), (Join-Path $bffDir 'Dockerfile'))

Write-Host ''
Write-Host '=== 경로 확인 ===' -ForegroundColor Cyan
Write-Host "  db  : $dbDir"
Write-Host "  was : $wasDir"
Write-Host "  bff : $bffDir"

# docker compose 가 참조할 빌드 컨텍스트를 .env 로 넘긴다.
# compose 파일에 상대 경로를 박으면 배치가 다를 때 조용히 엉뚱한 곳을 빌드한다.
$wasContext = $wasDir
$bffContext = $bffDir

# ---------------------------------------------------------------------
# 파일 입출력 - PowerShell 5.1 / 7 공용
#
#   ⚠️ -Encoding utf8NoBOM 은 PowerShell 7 전용이다. 5.1 에서는
#      "식별자 이름 utf8NoBOM 을 유효한 열거자 이름과 일치시킬 수 없습니다" 로 실패한다.
#   ⚠️ 5.1 의 -Encoding UTF8 은 BOM 을 붙인다. BOM 이 붙은 SQL 은
#      MySQL 클라이언트가 첫 구문을 깨뜨린다 (README §6.10).
#   → .NET API 로 직접 쓴다. 양쪽에서 동일하게 BOM 없는 UTF-8 이 나온다.
# ---------------------------------------------------------------------
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-Utf8NoBom {
    param([string] $Path, [string[]] $Content)
    $text = ($Content -join "`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $text, $script:Utf8NoBom)
}

function Read-Utf8 {
    param([string] $Path)
    # Get-Content -Raw 는 5.1 에서 ANSI(CP949)로 읽어 한글을 깨뜨린다.
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Assert-Docker {
    docker version --format '{{.Server.Version}}' 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[ERROR] Docker 에 접근할 수 없다. Docker Desktop 을 기동한다.' -ForegroundColor Red
        exit 1
    }
}

function New-RandomPassword {
    param([int] $Length = 24)
    # MySQL 자리표시자 치환과 셸 인용을 깨지 않는 문자만 쓴다.
    # ' " $ ` \ 는 제외한다.
    # ⚠️ '#' 을 넣지 않는다. .env 파서가 주석 시작으로 볼 수 있다.
    # ⚠️ ' " $ ` \ 도 제외한다. SQL 치환과 셸 인용을 깨뜨린다.
    $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789-_'
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = [byte[]]::new($Length)
    $rng.GetBytes($bytes)
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

function New-SigningKey {
    # HS256 은 32바이트 이상을 요구한다. 넉넉히 48자를 만든다.
    # 로컬 전용이다. 운영 키는 Secrets Manager 'bff-secret' 에서 온다 (§3.1).
    return New-RandomPassword -Length 48
}

function New-BcryptHash {
    param([string] $Plain)
    $inner = "tr -d '\r\n' > /tmp/p; htpasswd -inBC 10 u < /tmp/p; rm -f /tmp/p"
    $out = $Plain | docker run --rm -i $HTPASSWD_IMG sh -c $inner
    $hash = (($out | Where-Object { $_ -match ':' } | Select-Object -First 1) -split ':', 2)[1].Trim()
    if ($hash.StartsWith('$2y$')) { $hash = '$2b$' + $hash.Substring(4) }
    if ($hash.Length -ne 60) { throw "BCrypt 해시 길이 오류: $($hash.Length)" }
    return $hash
}


# =====================================================================
Assert-Docker

Write-Host ''
Write-Host '=== 1. 베이스 이미지 digest 해석 ===' -ForegroundColor Cyan

docker pull $BASE_IMAGE | Out-Null
$repoDigest = docker inspect --format='{{index .RepoDigests 0}}' $BASE_IMAGE

if (-not $repoDigest -or $repoDigest -notmatch '@(sha256:[0-9a-f]{64})') {
    Write-Host "[ERROR] $BASE_IMAGE 의 digest 를 조회하지 못했다." -ForegroundColor Red
    exit 1
}
$digest = $Matches[1]

Write-Host "  $BASE_IMAGE"
Write-Host "  $digest" -ForegroundColor Green
Write-Host '  ⚠️ 이 값을 README §21 digest 표에 기록한다.' -ForegroundColor Yellow

foreach ($dockerfile in $dockerfiles) {

    $label = Split-Path (Split-Path $dockerfile -Parent) -Leaf
    $df = Read-Utf8 $dockerfile

    if ($df -match '__REPLACE_WITH_ACTUAL_DIGEST__') {
        $df = $df.Replace('sha256:__REPLACE_WITH_ACTUAL_DIGEST__', $digest)
        [System.IO.File]::WriteAllText($dockerfile, $df, $script:Utf8NoBom)
        Write-Host "  $label/Dockerfile : 자리표시자를 치환했다."
    }
    elseif ($df -match 'amazoncorretto:25-alpine@(sha256:[0-9a-f]{64})') {
        if ($Matches[1] -ne $digest) {
            Write-Host "  ⚠️ $label/Dockerfile 의 digest 가 현재 이미지와 다르다." -ForegroundColor Yellow
            Write-Host "     기존: $($Matches[1])"
            Write-Host "     현재: $digest"
            Write-Host '     의도한 핀이라면 그대로 둔다. 갱신하려면 직접 수정한다.'
        }
        else {
            Write-Host "  $label/Dockerfile : digest 최신"
        }
    }
}


Write-Host ''
Write-Host '=== 2. 자격증명 생성 ===' -ForegroundColor Cyan

if ((Test-Path $envFile) -and -not $Force) {
    Write-Host '  .env 가 이미 있다. 재사용한다. (-Force 로 재발급)'
    $lines = @((Read-Utf8 $envFile) -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
    $appWasPassword = (($lines | Where-Object { $_ -like 'APP_WAS_PASSWORD=*' }) -split '=', 2)[1]
    # 경로는 매번 갱신한다. 리포를 옮겼는데 옛 경로로 빌드하는 사고를 막는다.
    $lines = $lines | Where-Object {
        $_ -notlike 'WAS_CONTEXT=*' -and $_ -notlike 'BFF_CONTEXT=*'
    }

    # 배치 3c 이전에 만들어진 .env 에는 BFF 용 키가 없다. 없으면 보충한다.
    # 있으면 유지한다 - 서명키가 바뀌면 발급된 토큰이 전부 무효가 된다.
    if (-not ($lines | Where-Object { $_ -like 'JWT_SIGNING_KEY=*' })) {
        $lines = $lines + "JWT_SIGNING_KEY=$(New-SigningKey)"
        Write-Host '  JWT_SIGNING_KEY 를 새로 발급했다 (기존 .env 에 없었다).'
    }
    if (-not ($lines | Where-Object { $_ -like 'COOKIE_SECURE=*' })) {
        $lines = $lines + 'COOKIE_SECURE=false'
        Write-Host '  COOKIE_SECURE=false 를 추가했다 (로컬 http).'
    }

    Write-Utf8NoBom -Path $envFile -Content ($lines + @(
        "WAS_CONTEXT=$($wasContext -replace '\\','/')",
        "BFF_CONTEXT=$($bffContext -replace '\\','/')"
    ))
}
else {
    $appWasPassword = New-RandomPassword
    $rootPassword   = New-RandomPassword
    Write-Utf8NoBom -Path $envFile -Content @(
        '# local/prepare.ps1 이 생성했다. 로컬 전용이며 커밋되지 않는다.',
        "MYSQL_ROOT_PASSWORD=$rootPassword",
        "APP_WAS_PASSWORD=$appWasPassword",
        "JWT_SIGNING_KEY=$(New-SigningKey)",
        '',
        '# 로컬은 http 다. Secure 쿠키는 저장되지 않으므로 false 로 낮춘다.',
        '# 운영(EKS)은 반드시 true. 이 값을 그대로 배포하지 않는다.',
        'COOKIE_SECURE=false',
        '',
        "WAS_CONTEXT=$($wasContext -replace '\\','/')",
        "BFF_CONTEXT=$($bffContext -replace '\\','/')"
    )
    Write-Host '  .env 발급 완료 (비밀번호 24자 / JWT 서명키 48자)'
}

Write-Host '  직원 BCrypt 해시 생성 중...'
$hash = New-BcryptHash -Plain $LOCAL_STAFF_PASSWORD
Write-Host "  $($hash.Substring(0,7))... (60자)"


Write-Host ''
Write-Host '=== 3. mysql-init 생성 ===' -ForegroundColor Cyan

if (Test-Path $initDir) { Remove-Item -Recurse -Force $initDir }
New-Item -ItemType Directory -Path $initDir | Out-Null

# 01 - 그대로 복사
Copy-Item (Join-Path $dbDir '01_schema.sql') (Join-Path $initDir '01_schema.sql')
Write-Host '  01_schema.sql'

# 02 - app_was 비밀번호 치환
$grants = Read-Utf8 (Join-Path $dbDir '02_grants.sql')
$grants = $grants.Replace('__APP_WAS_PASSWORD__', $appWasPassword)
[System.IO.File]::WriteAllText((Join-Path $initDir '02_grants.sql'), $grants, $script:Utf8NoBom)
Write-Host '  02_grants.sql   (비밀번호 치환)'

# 03 - BCrypt 해시 4개 치환
$seed = Read-Utf8 (Join-Path $dbDir '03_seed.sql')
foreach ($token in @('__HASH_DOC_KIM__', '__HASH_DOC_LEE__', '__HASH_NUR_PARK__', '__HASH_ADM_CHOI__')) {
    $seed = $seed.Replace($token, $hash)
}
[System.IO.File]::WriteAllText((Join-Path $initDir '03_seed.sql'), $seed, $script:Utf8NoBom)
Write-Host '  03_seed.sql     (해시 4개 치환)'

# 04 - 그대로 복사 (5.8MB)
Copy-Item (Join-Path $dbDir '04_icd_seed.sql') (Join-Path $initDir '04_icd_seed.sql')
Write-Host '  04_icd_seed.sql (5.8MB)'

# 치환 누락 검사 - 자리표시자가 남으면 컨테이너 안에서 조용히 실패한다
$leftover = Select-String -Path (Join-Path $initDir '*.sql') -Pattern '__[A-Z_]+__' -List
if ($leftover) {
    Write-Host ''
    Write-Host '[ERROR] 치환되지 않은 자리표시자가 남아 있다:' -ForegroundColor Red
    $leftover | ForEach-Object { Write-Host "  $($_.Filename): $($_.Matches[0].Value)" }
    exit 1
}


Write-Host ''
Write-Host '=== 준비 완료 ===' -ForegroundColor Green
Write-Host ''
Write-Host '로컬 테스트 계정 (4개 전부 동일 비밀번호)'
Write-Host "  doc_kim / doc_lee / nur_park / adm_choi"
Write-Host "  비밀번호: $LOCAL_STAFF_PASSWORD" -ForegroundColor DarkGray
Write-Host ''
Write-Host '다음 단계' -ForegroundColor Cyan
Write-Host '  docker compose up --build -d --wait     # --wait 필수'
Write-Host '  .\verify-was.ps1                        # WAS 직접 검증 (36개)'
Write-Host '  .\verify-bff.ps1                        # BFF 경유 검증 (39개)'
Write-Host ''
Write-Host '⚠️ 재실행 시 반드시 볼륨을 지운다. init 스크립트는 빈 볼륨에서만 돈다.' -ForegroundColor Yellow
Write-Host '   docker compose down -v'
Write-Host ''

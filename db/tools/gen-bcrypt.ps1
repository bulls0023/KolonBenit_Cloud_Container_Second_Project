<#
.SYNOPSIS
    03_seed.sql 직원 계정용 BCrypt 해시 생성기.

.DESCRIPTION
    Hybrid Toy Project - db/tools/gen-bcrypt.ps1
    계약: README v3.1 §6.8 (BCrypt 해시만 저장) / 구축설명서 §3.1-4

    Spring Security 의 BCryptPasswordEncoder 와 호환되는 해시를 만든다.
    Docker 컨테이너의 htpasswd 를 사용하므로 로컬에 별도 설치가 필요 없다.

    이 스크립트가 하지 않는 것
      - 평문 비밀번호를 파일에 쓰지 않는다
      - 평문을 명령행 인자로 넘기지 않는다 (호스트 프로세스 목록에 노출된다)
      - 결과를 클립보드나 로그에 자동 복사하지 않는다

    산출물 취급
      출력된 해시는 03_seed.sql 의 자리표시자에 붙여 넣고,
      치환본(_03_seed.local.sql)은 실행 직후 삭제한다.
      평문 비밀번호는 채팅, PR, 이슈, 스크린샷 어디에도 남기지 않는다.

.PARAMETER LoginId
    해시를 생성할 대상 계정. 생략 시 03_seed.sql 의 4개 계정 전부.

.PARAMETER Cost
    BCrypt 코스트 팩터. 기본 10. WAS 의 BCryptPasswordEncoder 기본값과 맞춘다.

.PARAMETER Verify
    생성 대신 검증 모드. 기존 해시와 비밀번호가 맞는지 확인한다. -Hash 필요.

.EXAMPLE
    .\gen-bcrypt.ps1
    4개 계정의 해시를 순서대로 생성한다.

.EXAMPLE
    .\gen-bcrypt.ps1 -LoginId doc_kim
    doc_kim 하나만 다시 생성한다.

.EXAMPLE
    .\gen-bcrypt.ps1 -Verify -Hash '<60자 해시>'
    비밀번호가 해당 해시와 일치하는지 확인한다.
#>

[CmdletBinding()]
param(
    [string[]] $LoginId,

    [ValidateRange(4, 16)]
    [int]      $Cost = 10,

    [switch]   $Verify,

    [string]   $Hash
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$IMAGE            = 'httpd:2.4-alpine'
$DEFAULT_ACCOUNTS = @('doc_kim', 'doc_lee', 'nur_park', 'adm_choi')


# ---------------------------------------------------------------------
# 사전 점검
# ---------------------------------------------------------------------
function Test-Prerequisite {
    docker version --format '{{.Server.Version}}' 2>$null | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host '[ERROR] Docker 에 접근할 수 없다.' -ForegroundColor Red
        Write-Host '        Docker Desktop 을 기동한 뒤 다시 실행한다.'
        Write-Host ''
        Write-Host '        Docker 를 쓸 수 없는 환경이라면 WAS 담당에게 요청한다.'
        Write-Host '        Spring 프로젝트에서 아래 한 줄이면 동일한 결과가 나온다:'
        Write-Host '          new BCryptPasswordEncoder(10).encode("평문")' -ForegroundColor DarkGray
        Write-Host ''
        exit 1
    }

    $cached = docker images -q $IMAGE 2>$null

    if (-not $cached) {
        Write-Host "[INFO ] $IMAGE 이미지를 내려받는다 (최초 1회, 약 10MB)..." -ForegroundColor DarkGray
        docker pull $IMAGE | Out-Null

        if ($LASTEXITCODE -ne 0) {
            Write-Host '[ERROR] 이미지 pull 실패. 네트워크를 확인한다.' -ForegroundColor Red
            exit 1
        }
    }
}


# ---------------------------------------------------------------------
# SecureString -> 평문. 메모리에서만 존재하며 사용 후 즉시 해제한다.
# ---------------------------------------------------------------------
function ConvertFrom-SecureStringPlain {
    param([Security.SecureString] $Secure)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}


# ---------------------------------------------------------------------
# BCrypt 해시 생성
#
#   htpasswd -inBC <cost> <user>
#     -i  비밀번호를 stdin 으로 읽는다   <- 인자로 넘기지 않는 이유
#     -n  파일에 쓰지 않고 stdout 으로 출력
#     -B  bcrypt
#     -C  코스트 팩터
#
#   출력 형식: u:<해시>
#
#   [확인됨] 개행 처리
#     htpasswd -i 는 입력 끝의 LF 와 CRLF 를 스스로 제거한다. 실측으로 확인했다.
#     따라서 Windows PowerShell 5.1 의 CRLF 파이프 출력은 그대로도 정상 동작한다.
#     다만 CR 단독(\r, LF 없음)은 제거되지 않아 "평문+\r" 의 해시가 만들어진다.
#     이 경우 WAS 로그인이 100% 실패하며 원인 추적이 매우 어렵다.
#     비용이 0 이므로 컨테이너 안에서 tr 로 먼저 제거해 경우의 수를 없앤다.
#
#   [중요] 접두사 정규화
#     htpasswd 는 $2y$ 를 쓴다. Spring 의 BCryptPasswordEncoder 는
#     $2a$ / $2b$ / $2y$ 를 모두 허용하므로 그대로도 검증은 통과한다.
#     다만 구축설명서 §5-1 의 검증 기준이 "$2b$ 로 시작" 이므로 표기를 맞춘다.
#     $2y$ 와 $2b$ 는 동일 알고리즘의 다른 표기다. 값을 바꾸는 것이 아니다.
# ---------------------------------------------------------------------
function New-BcryptHash {
    param(
        [string] $Plain,
        [int]    $CostFactor
    )

    $inner = "tr -d '\r\n' > /tmp/p; htpasswd -inBC $CostFactor u < /tmp/p; rm -f /tmp/p"
    $out   = $Plain | docker run --rm -i $IMAGE sh -c $inner

    if ($LASTEXITCODE -ne 0 -or -not $out) {
        throw 'htpasswd 실행 실패. Docker 상태를 확인한다.'
    }

    $line = ($out | Where-Object { $_ -match ':' } | Select-Object -First 1)
    $hash = ($line -split ':', 2)[1].Trim()

    if ($hash.StartsWith('$2y$')) {
        $hash = '$2b$' + $hash.Substring(4)
    }

    # 자기 검증. 60자가 아니면 CHAR(60) 컬럼에서 조용히 깨진다.
    if ($hash.Length -ne 60) {
        throw "생성된 해시 길이가 $($hash.Length) 이다. 60이어야 한다. 산출물을 사용하지 않는다."
    }

    if ($hash -notmatch '^\$2b\$\d{2}\$[./A-Za-z0-9]{53}$') {
        throw '생성된 해시 형식이 BCrypt 가 아니다. 산출물을 사용하지 않는다.'
    }

    return $hash
}


# ---------------------------------------------------------------------
# 검증 모드
# ---------------------------------------------------------------------
function Invoke-VerifyMode {
    if (-not $Hash) {
        Write-Host '[ERROR] -Verify 에는 -Hash 가 필요하다.' -ForegroundColor Red
        exit 1
    }

    $secure = Read-Host '검증할 비밀번호' -AsSecureString
    $plain  = ConvertFrom-SecureStringPlain $secure

    try {
        $inner = 'printf "%s\n" "$HLINE" > /tmp/h; tr -d "\r\n" > /tmp/p; ' +
                 'htpasswd -vi /tmp/h u < /tmp/p; rm -f /tmp/h /tmp/p'

        $plain | docker run --rm -i -e "HLINE=u:$Hash" $IMAGE sh -c $inner 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Host '[OK   ] 비밀번호가 해시와 일치한다.' -ForegroundColor Green
        }
        else {
            Write-Host '[FAIL ] 일치하지 않는다.' -ForegroundColor Red
        }
    }
    finally {
        $plain = $null
        [GC]::Collect()
    }
}


# =====================================================================
# 본문
# =====================================================================
Test-Prerequisite

if ($Verify) {
    Invoke-VerifyMode
    exit 0
}

$targets = if ($LoginId) { $LoginId } else { $DEFAULT_ACCOUNTS }

Write-Host ''
Write-Host '=== BCrypt 해시 생성 ===' -ForegroundColor Cyan
Write-Host "코스트 팩터 : $Cost"
Write-Host "대상 계정   : $($targets -join ', ')"
Write-Host ''
Write-Host '평문 비밀번호는 화면에 표시되지 않는다.' -ForegroundColor Yellow
Write-Host '팀 내부 합의된 테스트 비밀번호를 사용하고, 문서화하지 않는다.' -ForegroundColor Yellow
Write-Host ''

$results = @()

foreach ($id in $targets) {

    $secure = Read-Host "[$id] 비밀번호" -AsSecureString
    $plain  = ConvertFrom-SecureStringPlain $secure

    try {
        if ([string]::IsNullOrWhiteSpace($plain)) {
            Write-Host '       빈 비밀번호는 허용하지 않는다. 건너뛴다.' -ForegroundColor Red
            continue
        }

        if ($plain.Length -lt 8) {
            Write-Host '       8자 미만이다. 건너뛴다.' -ForegroundColor Red
            continue
        }

        # BCrypt 는 72바이트 초과분을 잘라낸다. 조용한 절단은 사고다.
        if ([Text.Encoding]::UTF8.GetByteCount($plain) -gt 72) {
            Write-Host '       72바이트를 초과한다. BCrypt 가 뒤를 잘라낸다. 건너뛴다.' -ForegroundColor Red
            continue
        }

        $results += [PSCustomObject]@{
            login_id      = $id
            password_hash = (New-BcryptHash -Plain $plain -CostFactor $Cost)
        }
    }
    finally {
        $plain = $null
    }
}

[GC]::Collect()

if ($results.Count -eq 0) {
    Write-Host ''
    Write-Host '생성된 해시가 없다.' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '=== 결과 - 03_seed.sql 자리표시자에 붙여 넣는다 ===' -ForegroundColor Cyan
Write-Host ''

foreach ($r in $results) {
    $token = '__HASH_' + $r.login_id.ToUpper() + '__'
    Write-Host ("  {0,-20} -> {1}" -f $token, $r.password_hash)
}

Write-Host ''
Write-Host '다음 단계' -ForegroundColor Cyan
Write-Host '  1. 사본 생성   : Copy-Item .\03_seed.sql .\_03_seed.local.sql'
Write-Host '  2. 사본에서 위 자리표시자를 치환한다 (원본은 건드리지 않는다)'
Write-Host '  3. 사본으로 실행한다'
Write-Host '  4. 사본 삭제   : Remove-Item .\_03_seed.local.sql -Force'
Write-Host ''
Write-Host '03_seed.sql 원본에 해시를 적어 커밋하지 않는다.' -ForegroundColor Yellow
Write-Host '  커밋 전 확인 : Select-String -Path .\03_seed.sql -Pattern ''\$2[aby]\$''' -ForegroundColor DarkGray
Write-Host ''

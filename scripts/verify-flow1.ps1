<#
.SYNOPSIS
    흐름1 (G2) 검증. 외부 환자 경로.

.DESCRIPTION
    Hybrid Toy Project - scripts/verify-flow1.ps1
    계약: README v3.1 §6.9 / §14 / 구축설명서 §11.1

    verify-bff.ps1 이 BFF 를 직접 때렸다면, 이 스크립트는
    실제 도메인 -> Cloudflare -> ALB -> Ingress 경로를 통과한다.

    여기서 처음 검증되는 것
      - HTTPS 종단 (ACM 인증서)
      - Ingress 2-path 라우팅 순서
      - patient-web 정적 서빙
      - 직원 API 의 외부 404
      - Secure 쿠키가 HTTPS 에서 실제로 저장되는지

.PARAMETER BaseUrl
    기본 https://www.kuspitalsoldeskproject.org
    ALB DNS 로 직접 치려면 -BaseUrl 로 넘긴다 (인증서 불일치 경고 발생).
#>

[CmdletBinding()]
param(
    [string] $BaseUrl = 'https://www.kuspitalsoldeskproject.org'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:Pass = 0
$script:Fail = 0
$script:Results = @()
$script:Session = $null

# PowerShell 5.1 은 TLS 1.2 를 기본으로 쓰지 않는다. 명시하지 않으면
# ALB 핸드셰이크가 실패하고 원인이 인증서 문제로 보인다.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


function Invoke-Api {
    param(
        [string] $Method,
        [string] $Path,
        [hashtable] $Headers = @{},
        [object] $Body = $null,
        [switch] $NewSession
    )

    $clean = @{}
    foreach ($k in $Headers.Keys) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Headers[$k])) { $clean[$k] = $Headers[$k] }
    }

    $params = @{
        Method          = $Method
        Uri             = "$BaseUrl$Path"
        Headers         = $clean
        ContentType     = 'application/json; charset=utf-8'
        ErrorAction     = 'Stop'
        UseBasicParsing = $true
        TimeoutSec      = 20
    }

    if ($NewSession)                  { $params.SessionVariable = 'newSess' }
    elseif ($null -ne $script:Session) { $params.WebSession = $script:Session }

    if ($null -ne $Body) {
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 6 -Compress))
    }

    try {
        $res = Invoke-WebRequest @params
        if ($NewSession) { $script:Session = $newSess }
        return [PSCustomObject]@{
            Status  = [int]$res.StatusCode
            Body    = if ($res.Content) { try { $res.Content | ConvertFrom-Json } catch { $null } } else { $null }
            Raw     = $res.Content
            Headers = $res.Headers
        }
    }
    catch {
        $resp = $null
        try { if ($_.Exception.PSObject.Properties['Response']) { $resp = $_.Exception.Response } } catch { }

        if ($null -eq $resp) {
            return [PSCustomObject]@{ Status = -1; Body = $null; Raw = $_.Exception.Message; Headers = $null }
        }

        $status = if ($resp.PSObject.Properties['StatusCode'].Value -is [int]) {
                      [int]$resp.StatusCode
                  } else { [int]$resp.StatusCode.value__ }

        $raw = $null
        try { if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $raw = $_.ErrorDetails.Message } } catch { }
        if ([string]::IsNullOrWhiteSpace($raw)) {
            try {
                $st = $resp.GetResponseStream()
                if ($st) {
                    $rd = New-Object System.IO.StreamReader($st, [System.Text.Encoding]::UTF8)
                    $raw = $rd.ReadToEnd(); $rd.Close()
                }
            } catch { }
        }

        $parsed = $null
        if ($raw) { try { $parsed = $raw | ConvertFrom-Json } catch { } }
        return [PSCustomObject]@{ Status = $status; Body = $parsed; Raw = $raw; Headers = $null }
    }
}

function Get-Cookie {
    param([string] $Name)
    if ($null -eq $script:Session) { return $null }
    foreach ($c in $script:Session.Cookies.GetCookies("$BaseUrl/api/bff/patient")) {
        if ($c.Name -eq $Name) { return $c }
    }
    return $null
}

function Csrf {
    $c = Get-Cookie 'XSRF-TOKEN'
    if ($null -eq $c) {
        Invoke-Api GET '/api/bff/patient/auth/csrf' | Out-Null
        $c = Get-Cookie 'XSRF-TOKEN'
    }
    if ($null -eq $c) { return @{} }
    return @{ 'X-XSRF-TOKEN' = $c.Value }
}

function Test-Case {
    param(
        [string] $Name,
        [int]    $ExpectStatus,
        [object] $Response,
        [string] $ExpectError = $null,
        [scriptblock] $Extra = $null
    )

    $ok = ($Response.Status -eq $ExpectStatus)
    $detail = "status=$($Response.Status)"

    if ($ok -and $ExpectError) {
        $actual = if ($Response.Body -and $Response.Body.PSObject.Properties['error']) {
                      $Response.Body.error } else { '(없음)' }
        $ok = ($actual -eq $ExpectError)
        $detail += " error=$actual"
    }
    if ($ok -and $Extra) {
        try   { $ok = [bool](& $Extra $Response) }
        catch { $ok = $false; $detail += ' extra=예외' }
    }

    if ($ok) {
        $script:Pass++
        Write-Host ("  [PASS] {0,-46} {1}" -f $Name, $detail) -ForegroundColor Green
    } else {
        $script:Fail++
        Write-Host ("  [FAIL] {0,-46} {1}" -f $Name, $detail) -ForegroundColor Red
        if ($Response.Raw) {
            $t = [string]$Response.Raw
            if ($t.Length -gt 200) { $t = $t.Substring(0, 200) + '…' }
            Write-Host "         $t" -ForegroundColor DarkGray
        }
    }
    $script:Results += [PSCustomObject]@{ Name = $Name; Ok = $ok; Detail = $detail }
}


# =====================================================================
Write-Host ''
Write-Host "=== 흐름1 (G2) 검증 : $BaseUrl ===" -ForegroundColor Cyan
Write-Host ''

Write-Host '[진입 · 라우팅]' -ForegroundColor Cyan

$root = Invoke-Api GET '/'
Test-Case '루트 200 (patient-web 도달)' 200 $root `
    -Extra { param($r) $r.Raw -match '구스피탈' }

Test-Case 'HTTPS 종단 성공' 200 $root -Extra { param($r) $BaseUrl.StartsWith('https://') }

Test-Case '/healthz 200 (ALB 헬스체크 경로)' 200 (Invoke-Api GET '/healthz')

# 🚨 이 항목이 §6.9 의 핵심이다.
Test-Case '직원 API 는 외부에서 404' 404 (Invoke-Api GET '/api/bff/staff/patients') 'not_found'

Test-Case '환자 API 는 BFF 로 라우팅 (401)' 401 `
    (Invoke-Api GET '/api/bff/patient/appointments') 'unauthorized'

Write-Host ''
Write-Host '[환자 인증 · Secure 쿠키]' -ForegroundColor Cyan

$csrf = Invoke-Api GET '/api/bff/patient/auth/csrf' -NewSession
Test-Case 'CSRF 발급 204' 204 $csrf

Test-Case 'XSRF-TOKEN 수신 (Secure)' 204 $csrf -Extra {
    param($r) $null -ne (Get-Cookie 'XSRF-TOKEN')
}

$suffix  = Get-Random -Maximum 99999
$loginId = "g2$suffix"

$reg = Invoke-Api POST '/api/bff/patient/auth/register' (Csrf) @{
    login_id = $loginId; password = 'Patient!2026'; name = 'G2검증'
    birth_date = '1992-03-03'; phone = '010-3333-4444'
}
Test-Case '가입 201' 201 $reg -Extra { param($r) $null -ne $r.Body.actor_id }

# HTTPS 에서 Secure 쿠키가 실제로 저장되는지. 로컬 http 에서는 검증 불가였다.
$pt = Get-Cookie 'PATIENT_TOKEN'
Test-Case 'PATIENT_TOKEN 저장됨 (HTTPS Secure)' 201 $reg -Extra { param($r) $null -ne $pt }
Test-Case 'PATIENT_TOKEN HttpOnly' 201 $reg -Extra { param($r) $null -ne $pt -and $pt.HttpOnly }
Test-Case 'PATIENT_TOKEN Secure' 201 $reg -Extra { param($r) $null -ne $pt -and $pt.Secure }
Test-Case 'PATIENT_TOKEN Path 제한' 201 $reg `
    -Extra { param($r) $null -ne $pt -and $pt.Path -eq '/api/bff/patient' }
Test-Case '응답에 토큰 문자열 없음' 201 $reg -Extra { param($r) $r.Raw -notmatch 'token' }

Test-Case '로그인 200' 200 (Invoke-Api POST '/api/bff/patient/auth/login' (Csrf) `
    @{ login_id = $loginId; password = 'Patient!2026' })

Write-Host ''
Write-Host '[환자 업무]' -ForegroundColor Cyan

$doctors = Invoke-Api GET '/api/bff/patient/doctors'
Test-Case '의사 목록 200' 200 $doctors -Extra { param($r) @($r.Body).Count -ge 2 }
$doctorId = if (@($doctors.Body).Count -gt 0) { @($doctors.Body)[0].doctor_id } else { 1 }

# 시각 의존을 없앤다. 오늘부터 6일까지 훑어 첫 가용 날짜를 쓴다.
$slots = $null; $slotDate = $null
for ($d = 0; $d -le 6; $d++) {
    $try = (Get-Date).AddDays($d).ToString('yyyy-MM-dd')
    $r = Invoke-Api GET "/api/bff/patient/slots?doctorId=$doctorId&date=$try"
    if ($r.Status -eq 200 -and @($r.Body).Count -gt 0) { $slots = $r; $slotDate = $try; break }
    if ($null -eq $slots) { $slots = $r }
}
Write-Host "         (예약 대상 날짜: $slotDate)" -ForegroundColor DarkGray
Test-Case '슬롯 조회 200' 200 $slots -Extra { param($r) @($r.Body).Count -gt 0 }
$slotId = if (@($slots.Body).Count -gt 0) { @($slots.Body)[0].slot_id } else { 0 }

$book = Invoke-Api POST '/api/bff/patient/appointments' (Csrf) @{
    slot_id = $slotId; symptom = 'G2 검증 예약'
}
Test-Case '예약 201 + visit_no' 201 $book `
    -Extra { param($r) $r.Body.visit_no -match '^V\d{8}-\d{4}$' }

Test-Case '내 예약 조회 200' 200 (Invoke-Api GET '/api/bff/patient/appointments') `
    -Extra { param($r) @($r.Body).Count -ge 1 }

Test-Case '처방전 조회 200' 200 (Invoke-Api GET '/api/bff/patient/prescriptions')

Write-Host ''
Write-Host '[계약 형식]' -ForegroundColor Cyan

Test-Case 'JSON 키가 snake_case' 200 (Invoke-Api GET '/api/bff/patient/appointments') `
    -Extra { param($r) $r.Raw -match 'visit_no' -and $r.Raw -notmatch 'visitNo' }

Test-Case '로그아웃 204' 204 (Invoke-Api POST '/api/bff/patient/auth/logout' (Csrf))
Test-Case '로그아웃 후 401' 401 (Invoke-Api GET '/api/bff/patient/appointments') 'unauthorized'


# =====================================================================
Write-Host ''
Write-Host '=====================================================' -ForegroundColor Cyan
Write-Host ("  PASS {0}  /  FAIL {1}  /  총 {2}" -f $script:Pass, $script:Fail, ($script:Pass + $script:Fail))
Write-Host '=====================================================' -ForegroundColor Cyan

if ($script:Fail -gt 0) {
    Write-Host ''
    Write-Host '실패 항목:' -ForegroundColor Red
    $script:Results | Where-Object { -not $_.Ok } | ForEach-Object {
        Write-Host "  - $($_.Name)  [$($_.Detail)]" -ForegroundColor Red
    }
    Write-Host ''
    Write-Host '  kubectl -n app get ingress patient-web' -ForegroundColor DarkGray
    Write-Host '  kubectl -n app logs -l app=patient-web --tail=50' -ForegroundColor DarkGray
    Write-Host '  kubectl -n app logs -l app=bff --tail=50' -ForegroundColor DarkGray
    exit 1
}

Write-Host ''
Write-Host '전 항목 통과. 흐름1 (G2) 검증 완료.' -ForegroundColor Green
Write-Host ''

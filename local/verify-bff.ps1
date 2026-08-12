<#
.SYNOPSIS
    BFF 계약 검증. 39개 시나리오.

.DESCRIPTION
    Hybrid Toy Project - local/verify-bff.ps1
    계약: README v3.1 §6.5 / §6.6 / §6.7 / 구축설명서 §11

    verify-was.ps1 이 WAS 를 직접 때렸다면, 이 스크립트는 BFF 를 통과한다.
    즉 인증·인가·쿠키·CSRF·바인딩·통과전달이 검증 대상이다.

    검증 대상 중 여기서 처음 확인되는 것
      - 외부가 보낸 X-Actor-* 제거      (위조 방어 1번 원칙)
      - 전달수단 <-> actor_type 바인딩   (직원 토큰을 쿠키로 보내면 401)
      - 환자 쿠키 속성 (HttpOnly / Path / SameSite)
      - 응답 JSON 에 환자 토큰 미포함
      - CSRF (환자 경로만 적용, 직원 경로 면제)
      - WAS 4xx 통과 전달 / trace_id 연속성

.PARAMETER BaseUrl
    BFF 주소. 기본 http://localhost:18081
#>

[CmdletBinding()]
param(
    [string] $BaseUrl = 'http://localhost:18081',
    [string] $StaffPassword = 'Local!Hospital2026'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:Pass = 0
$script:Fail = 0
$script:Results = @()

# 환자 세션. 쿠키(PATIENT_TOKEN / XSRF-TOKEN)를 담는다.
$script:PatientSession = $null


# ---------------------------------------------------------------------
# HTTP 헬퍼 - PowerShell 5.1 / 7 공용
# ---------------------------------------------------------------------
function Invoke-Api {
    param(
        [string] $Method,
        [string] $Path,
        [hashtable] $Headers = @{},
        [object] $Body = $null,
        [Microsoft.PowerShell.Commands.WebRequestSession] $Session = $null,
        [switch] $NewSession
    )

    # ⚠️ 값이 null 인 헤더를 넘기면 Invoke-WebRequest 가
    #    NullReferenceException 으로 죽는다. 예외가 WebException 이 아니라
    #    응답 객체를 만들 수 없고, 호출부 전체가 status=-1 로 무너진다.
    $clean = @{}
    foreach ($k in $Headers.Keys) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Headers[$k])) { $clean[$k] = $Headers[$k] }
    }

    $params = @{
        Method      = $Method
        Uri         = "$BaseUrl$Path"
        Headers     = $clean
        ContentType = 'application/json; charset=utf-8'
        ErrorAction = 'Stop'
        UseBasicParsing = $true
    }

    if ($NewSession)      { $params.SessionVariable = 'newSess' }
    elseif ($null -ne $Session) { $params.WebSession = $Session }

    if ($null -ne $Body) {
        # PowerShell 5.1 은 본문을 기본 인코딩으로 보낸다. 한글이 깨진다.
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes(
            ($Body | ConvertTo-Json -Depth 6 -Compress))
    }

    try {
        $res = Invoke-WebRequest @params
        $result = [PSCustomObject]@{
            Status  = [int]$res.StatusCode
            Body    = if ($res.Content) { try { $res.Content | ConvertFrom-Json } catch { $null } } else { $null }
            Raw     = $res.Content
            Headers = $res.Headers
            Session = if ($NewSession) { $newSess } else { $Session }
        }
        return $result
    }
    catch {
        # ⚠️ StrictMode 에서 존재하지 않는 프로퍼티 접근은 예외다.
        #    파라미터 바인딩 오류 등은 Exception 에 Response 가 없다.
        #    여기서 터지면 함수가 아무것도 반환하지 못해 호출부가 전부 무너진다.
        $resp = $null
        try {
            if ($_.Exception.PSObject.Properties['Response']) { $resp = $_.Exception.Response }
        } catch { }

        if ($null -eq $resp) {
            return [PSCustomObject]@{ Status = -1; Body = $null; Raw = $_.Exception.Message
                                      Headers = $null; Session = $Session }
        }

        $status = if ($resp.PSObject.Properties['StatusCode'].Value -is [int]) {
                      [int]$resp.StatusCode
                  } else { [int]$resp.StatusCode.value__ }

        $raw = $null
        try { if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $raw = $_.ErrorDetails.Message } } catch { }
        if ([string]::IsNullOrWhiteSpace($raw)) {
            try {
                $stream = $resp.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                    $raw = $reader.ReadToEnd(); $reader.Close()
                }
            } catch { }
        }

        $parsed = $null
        if ($raw) { try { $parsed = $raw | ConvertFrom-Json } catch { } }

        return [PSCustomObject]@{ Status = $status; Body = $parsed; Raw = $raw
                                  Headers = $null; Session = $Session }
    }
}

# ⚠️ 쿠키 조회 URI 에 경로를 포함해야 한다.
#    PATIENT_TOKEN / XSRF-TOKEN 은 Path=/api/bff/patient 로 저장된다 (§6.5).
#    CookieContainer.GetCookies(루트URI) 는 그 쿠키를 반환하지 않는다.
#    루트로 조회하면 "쿠키를 못 받았다" 로 오진하게 된다.
$script:CookiePathUri = "$BaseUrl/api/bff/patient"

function Get-Cookie {
    param([Microsoft.PowerShell.Commands.WebRequestSession] $Session, [string] $Name)
    if ($null -eq $Session) { return $null }
    foreach ($c in $Session.Cookies.GetCookies($script:CookiePathUri)) {
        if ($c.Name -eq $Name) { return $c }
    }
    return $null
}

function Get-CookieValue {
    param([Microsoft.PowerShell.Commands.WebRequestSession] $Session, [string] $Name)
    $c = Get-Cookie -Session $Session -Name $Name
    if ($null -eq $c) { return $null }
    return $c.Value
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
        Write-Host ("  [PASS] {0,-48} {1}" -f $Name, $detail) -ForegroundColor Green
    }
    else {
        $script:Fail++
        Write-Host ("  [FAIL] {0,-48} {1}" -f $Name, $detail) -ForegroundColor Red
        if ($Response.Raw) { Write-Host "         본문: $($Response.Raw)" -ForegroundColor DarkGray }
    }
    $script:Results += [PSCustomObject]@{ Name = $Name; Ok = $ok; Detail = $detail }
}

function Bearer {
    param([string] $Token)
    return @{ 'Authorization' = "Bearer $Token" }
}

function Wait-Ready {
    param([int] $TimeoutSec = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $shown = $false
    while ((Get-Date) -lt $deadline) {
        $r = Invoke-Api GET '/readyz'
        if ($r.Status -eq 200) { if ($shown) { Write-Host '' }; return $true }
        if (-not $shown) { Write-Host -NoNewline '  BFF 기동 대기 중'; $shown = $true }
        Write-Host -NoNewline '.'
        Start-Sleep -Seconds 2
    }
    if ($shown) { Write-Host '' }
    return $false
}


# =====================================================================
# ---------------------------------------------------------------------
# WAS 워밍업
#
#   BFF 의 /readyz 는 WAS 를 확인하지 않는다 (§7.9 종속 전파 방지).
#   따라서 BFF 가 healthy 여도 WAS 는 아직 콜드일 수 있다.
#   WAS 첫 요청은 Hibernate SQL 생성 + BCrypt + MVC 초기화가 겹쳐
#   BFF 의 read timeout 5초(§6.6)를 넘길 수 있다.
#
#   존재하지 않는 계정으로 직원 로그인을 한 번 친다.
#   - WAS 까지 실제로 도달한다
#   - 실존 계정의 실패 카운트를 건드리지 않는다
#   - CSRF 대상이 아니다 (직원 경로)
#
#   ⚠️ 이것은 검증 편의다. 운영에서 첫 요청이 느린 문제는
#      WAS 파드의 startupProbe 로 다뤄야 한다 (배치 4).
# ---------------------------------------------------------------------
function Invoke-Warmup {
    for ($i = 1; $i -le 3; $i++) {
        $r = Invoke-Api POST '/api/bff/staff/auth/login' @{} `
                @{ login_id = '__warmup_nonexistent__'; password = 'Warmup!2026' }
        if ($r.Status -eq 401) { return $true }
        Write-Host "  WAS 워밍업 $i/3 (status=$($r.Status))" -ForegroundColor DarkGray
        Start-Sleep -Seconds 3
    }
    return $false
}

if (-not (Wait-Ready)) {
    Write-Host ''
    Write-Host "[ERROR] $BaseUrl 에 연결할 수 없다." -ForegroundColor Red
    Write-Host '  docker compose ps'
    Write-Host '  docker compose logs bff --tail=100'
    Write-Host '  다음부터는: docker compose up --build -d --wait' -ForegroundColor Yellow
    exit 1
}

if (-not (Invoke-Warmup)) {
    Write-Host '  [WARN] WAS 워밍업이 401 을 받지 못했다. 첫 요청이 503 이 될 수 있다.' -ForegroundColor Yellow
    Write-Host '         docker compose logs was --tail=50' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host "=== BFF 계약 검증 : $BaseUrl ===" -ForegroundColor Cyan
Write-Host ''

# ---------- 헬스 ----------
Write-Host '[헬스 체크]' -ForegroundColor Cyan
Test-Case '/healthz 200' 200 (Invoke-Api GET '/healthz')
Test-Case '/readyz 200 (WAS 상태 미의존)' 200 (Invoke-Api GET '/readyz') `
    -Extra { param($r) $r.Raw -notmatch 'was' -and $r.Raw -notmatch 'upstream' }

# ---------- CSRF ----------
Write-Host ''
Write-Host '[CSRF]' -ForegroundColor Cyan

$csrf = Invoke-Api GET '/api/bff/patient/auth/csrf' -NewSession
$script:PatientSession = $csrf.Session
Test-Case 'CSRF 발급 204' 204 $csrf

$xsrf = Get-Cookie $script:PatientSession 'XSRF-TOKEN'
Test-Case 'XSRF-TOKEN 쿠키 수신' 204 $csrf -Extra { param($r) $null -ne $xsrf }
Test-Case 'XSRF-TOKEN 은 HttpOnly 아님 (JS 읽기 필요)' 204 $csrf `
    -Extra { param($r) $null -ne $xsrf -and -not $xsrf.HttpOnly }

$suffix  = Get-Random -Maximum 99999
$loginId = "bff$suffix"
$regBody = @{ login_id = $loginId; password = 'Patient!2026'; name = '비에프에프환자'
              birth_date = '1991-06-06'; phone = '010-1111-2222' }

# CSRF 헤더 없이 POST
Test-Case 'CSRF 헤더 없는 가입 403' 403 `
    (Invoke-Api POST '/api/bff/patient/auth/register' @{} $regBody -Session $script:PatientSession)

if ([string]::IsNullOrWhiteSpace((Get-CookieValue $script:PatientSession 'XSRF-TOKEN'))) {
    Write-Host ''
    Write-Host '[ERROR] XSRF-TOKEN 쿠키를 확보하지 못했다. 이후 전 시나리오가 무의미하다.' -ForegroundColor Red
    Write-Host '        확인: curl.exe -i http://localhost:18081/api/bff/patient/auth/csrf'
    Write-Host ''
    exit 1
}

# ⚠️ 토큰 값을 캐시하지 않는다.
#    CSRF 토큰은 요청에 따라 갱신될 수 있다. 최초 값을 재사용하면
#    두세 번째 POST 부터 403 이 나고, 원인을 인가 문제로 오진하게 된다.
#    브라우저와 동일하게 매 요청 직전 쿠키를 다시 읽는다.
function Csrf {
    $v = Get-CookieValue $script:PatientSession 'XSRF-TOKEN'

    # 쿠키가 사라졌으면 브라우저처럼 다시 받아온다.
    # 없는 채로 진행하면 이후 POST 가 전부 403 이 되고,
    # 인가 문제로 오진하게 된다.
    if ([string]::IsNullOrWhiteSpace($v)) {
        Write-Host '         (XSRF-TOKEN 이 없어 재발급받는다)' -ForegroundColor DarkGray
        $r = Invoke-Api GET '/api/bff/patient/auth/csrf' @{} -Session $script:PatientSession
        $v = Get-CookieValue $script:PatientSession 'XSRF-TOKEN'
    }

    if ([string]::IsNullOrWhiteSpace($v)) {
        Write-Host '  [ERROR] XSRF-TOKEN 재발급 실패' -ForegroundColor Red
        return @{}
    }
    return @{ 'X-XSRF-TOKEN' = $v }
}

# ---------- 환자 인증 ----------
Write-Host ''
Write-Host '[환자 인증]' -ForegroundColor Cyan

$reg = Invoke-Api POST '/api/bff/patient/auth/register' (Csrf) $regBody -Session $script:PatientSession
Test-Case '가입 201' 201 $reg -Extra { param($r) $null -ne $r.Body.actor_id }
$patientId = if ($reg.Body) { $reg.Body.actor_id } else { 0 }

$ptCookie = Get-Cookie $script:PatientSession 'PATIENT_TOKEN'
Test-Case 'PATIENT_TOKEN 쿠키 수신' 201 $reg -Extra { param($r) $null -ne $ptCookie }
Test-Case 'PATIENT_TOKEN 은 HttpOnly' 201 $reg `
    -Extra { param($r) $null -ne $ptCookie -and $ptCookie.HttpOnly }
Test-Case 'PATIENT_TOKEN Path=/api/bff/patient' 201 $reg `
    -Extra { param($r) $null -ne $ptCookie -and $ptCookie.Path -eq '/api/bff/patient' }
Test-Case '응답 JSON 에 토큰 없음' 201 $reg -Extra { param($r) $r.Raw -notmatch 'token' }

Test-Case '가입 중복 409 (WAS 본문 통과)' 409 `
    (Invoke-Api POST '/api/bff/patient/auth/register' (Csrf) $regBody -Session $script:PatientSession) `
    'patient_exists'

Test-Case '로그인 200' 200 `
    (Invoke-Api POST '/api/bff/patient/auth/login' (Csrf) `
        @{ login_id = $loginId; password = 'Patient!2026' } -Session $script:PatientSession)

Test-Case '잘못된 비밀번호 401 (WAS 본문 통과)' 401 `
    (Invoke-Api POST '/api/bff/patient/auth/login' (Csrf) `
        @{ login_id = $loginId; password = 'WrongPassword!!' } -Session $script:PatientSession) `
    'invalid_credentials'

# ---------- 직원 인증 ----------
Write-Host ''
Write-Host '[직원 인증]' -ForegroundColor Cyan

$doc = Invoke-Api POST '/api/bff/staff/auth/login' @{} @{ login_id = 'doc_kim'; password = $StaffPassword }
Test-Case '의사 로그인 200 + access_token' 200 $doc `
    -Extra { param($r) $r.Body.access_token -and $r.Body.token_type -eq 'Bearer' }
Test-Case '직원 TTL 8시간 (expires_in 28800)' 200 $doc -Extra { param($r) $r.Body.expires_in -eq 28800 }
Test-Case '직원 로그인은 CSRF 면제' 200 $doc -Extra { param($r) $r.Body.role -eq 'DOCTOR' }
$docToken = if ($doc.Body) { $doc.Body.access_token } else { '' }

$nur = Invoke-Api POST '/api/bff/staff/auth/login' @{} @{ login_id = 'nur_park'; password = $StaffPassword }
Test-Case '간호사 로그인 200 role=NURSE' 200 $nur -Extra { param($r) $r.Body.role -eq 'NURSE' }
$nurToken = if ($nur.Body) { $nur.Body.access_token } else { '' }

Test-Case '직원 잘못된 비밀번호 401' 401 `
    (Invoke-Api POST '/api/bff/staff/auth/login' @{} @{ login_id = 'doc_kim'; password = 'Nope!12345' }) `
    'invalid_credentials'

# ---------- 인증·바인딩 방어 ----------
Write-Host ''
Write-Host '[인증 방어 - BFF 1차 방어선]' -ForegroundColor Cyan

Test-Case '토큰 없이 환자 API 401' 401 (Invoke-Api GET '/api/bff/patient/appointments') 'unauthorized'
Test-Case '토큰 없이 직원 API 401' 401 (Invoke-Api GET '/api/bff/staff/patients') 'unauthorized'

Test-Case '직원 Bearer 로 환자 경로 401' 401 `
    (Invoke-Api GET '/api/bff/patient/appointments' (Bearer $docToken)) 'unauthorized'

Test-Case '환자 쿠키로 직원 경로 401' 401 `
    (Invoke-Api GET '/api/bff/staff/patients' @{} -Session $script:PatientSession) 'unauthorized'

Test-Case '위조 서명 Bearer 401' 401 `
    (Invoke-Api GET '/api/bff/staff/patients' (Bearer 'aaa.bbb.ccc')) 'unauthorized'

Test-Case 'DOCTOR 로 관리자 경로 403' 403 `
    (Invoke-Api GET '/api/bff/staff/admin/anything' (Bearer $docToken)) 'forbidden'

# ★ 핵심: 외부가 X-Actor-* 를 직접 주입
Test-Case '위조 X-Actor-* 주입 (토큰 없음) 401' 401 `
    (Invoke-Api GET '/api/bff/staff/patients' @{
        'X-Actor-Type' = 'STAFF'; 'X-Actor-Id' = '1'; 'X-Actor-Role' = 'DOCTOR' }) 'unauthorized'

Test-Case '위조 X-Actor-* + 환자 쿠키로 직원 경로 401' 401 `
    (Invoke-Api GET '/api/bff/staff/patients' @{
        'X-Actor-Type' = 'STAFF'; 'X-Actor-Id' = '1'; 'X-Actor-Role' = 'DOCTOR' } `
        -Session $script:PatientSession) 'unauthorized'

# ---------- 환자 업무 ----------
Write-Host ''
Write-Host '[환자 업무 - 통과 전달]' -ForegroundColor Cyan

$doctors = Invoke-Api GET '/api/bff/patient/doctors' @{} -Session $script:PatientSession
Test-Case '의사 목록 200' 200 $doctors -Extra { param($r) @($r.Body).Count -ge 2 }
$doctorId = if (@($doctors.Body).Count -gt 0) { @($doctors.Body)[0].doctor_id } else { 1 }

# 시각 의존을 없앤다. 오늘부터 6일까지 훑어 첫 가용 날짜를 쓴다.
$slots = $null
$slotDate = $null
for ($d = 0; $d -le 6; $d++) {
    $try = (Get-Date).AddDays($d).ToString('yyyy-MM-dd')
    $r = Invoke-Api GET "/api/bff/patient/slots?doctorId=$doctorId&date=$try" @{} -Session $script:PatientSession
    if ($r.Status -eq 200 -and @($r.Body).Count -gt 0) { $slots = $r; $slotDate = $try; break }
    if ($null -eq $slots) { $slots = $r }
}
Write-Host "         (예약 대상 날짜: $slotDate)" -ForegroundColor DarkGray
Test-Case '슬롯 조회 200 + 과거 없음' 200 $slots -Extra {
    param($r)
    if (@($r.Body).Count -eq 0) { return $false }
    $now = Get-Date
    foreach ($s in @($r.Body)) { if ([datetime]$s.slot_at -lt $now) { return $false } }
    return $true
}
$slotId = if (@($slots.Body).Count -gt 0) { @($slots.Body)[0].slot_id } else { 0 }

if ($slotId -eq 0) {
    Write-Host '  [WARN] 7일 범위 전체에 예약 가능 슬롯이 0건이다.' -ForegroundColor Yellow
    Write-Host '         이후 예약·처방 시나리오가 연쇄 실패한다.' -ForegroundColor Yellow
}

$book = Invoke-Api POST '/api/bff/patient/appointments' (Csrf) `
    @{ slot_id = $slotId; symptom = '기침' } -Session $script:PatientSession
Test-Case '예약 201 + visit_no' 201 $book -Extra { param($r) $r.Body.visit_no -match '^V\d{8}-\d{4}$' }
$visitNo = if ($book.Body) { $book.Body.visit_no } else { $null }

Test-Case 'JSON 키가 snake_case' 200 `
    (Invoke-Api GET '/api/bff/patient/appointments' @{} -Session $script:PatientSession) `
    -Extra { param($r) $r.Raw -match 'visit_no' -and $r.Raw -notmatch 'visitNo' }

# ---------- 진료·처방 ----------
Write-Host ''
Write-Host '[진료·처방]' -ForegroundColor Cyan

Test-Case '상병코드 검색 200 (한글 인코딩)' 200 `
    (Invoke-Api GET '/api/bff/staff/icd-codes?q=%EB%8B%B9%EB%87%A8' (Bearer $docToken)) `
    -Extra { param($r) @($r.Body).Count -gt 0 -and @($r.Body).Count -le 50 }

Test-Case '1자 검색 400 (WAS 본문 통과)' 400 `
    (Invoke-Api GET '/api/bff/staff/icd-codes?q=E' (Bearer $docToken)) 'validation_error'

$chartBody = @{
    visit_no = $visitNo; icd_code = 'E1140'
    chief_complaint = '기침, 미열'
    note = 'BFF 경유 검증'
    prescription_items = @(@{ drug_name = '아목시실린캡슐 250mg'; dosage = '1캡슐'
                              frequency = '1일 3회'; duration_days = 5 })
}

Test-Case 'NURSE 차트 작성 403 (WAS 최종 방어)' 403 `
    (Invoke-Api POST '/api/bff/staff/charts' (Bearer $nurToken) $chartBody) 'forbidden'

$chart = Invoke-Api POST '/api/bff/staff/charts' (Bearer $docToken) $chartBody
Test-Case 'DOCTOR 차트+처방 201 (CSRF 면제)' 201 $chart `
    -Extra { param($r) @($r.Body.prescription_items).Count -eq 1 }

Test-Case '동일 visit_no 재발급 409' 409 `
    (Invoke-Api POST '/api/bff/staff/charts' (Bearer $docToken) $chartBody) 'duplicate_prescription'

Test-Case '차트 조회 200' 200 `
    (Invoke-Api GET "/api/bff/staff/patients/$visitNo/chart" (Bearer $docToken)) `
    -Extra { param($r) @($r.Body.prescription_items).Count -eq 1 }

Test-Case '당일 예약 목록 200' 200 `
    (Invoke-Api GET '/api/bff/staff/patients' (Bearer $docToken)) `
    -Extra { param($r) @($r.Body).Count -ge 1 }

Test-Case '환자 본인 처방전 200 (1건)' 200 `
    (Invoke-Api GET '/api/bff/patient/prescriptions' @{} -Session $script:PatientSession) `
    -Extra { param($r) @($r.Body).Count -eq 1 }

# ---------- 계약 형식 ----------
Write-Host ''
Write-Host '[계약 형식]' -ForegroundColor Cyan

$err = Invoke-Api GET '/api/bff/patient/appointments'
Test-Case '오류 JSON 3필드' 401 $err -Extra {
    param($r)
    $r.Body.PSObject.Properties['error'] -and
    $r.Body.PSObject.Properties['message'] -and
    $r.Body.PSObject.Properties['trace_id']
}

$ok = Invoke-Api GET '/api/bff/patient/doctors' @{} -Session $script:PatientSession
Test-Case '성공 응답에 trace_id 없음' 200 $ok -Extra { param($r) $r.Raw -notmatch 'trace_id' }
Test-Case '응답 헤더에 X-Trace-Id' 200 $ok -Extra { param($r) $r.Headers['X-Trace-Id'] }

# ---------- 로그아웃 ----------
Write-Host ''
Write-Host '[로그아웃]' -ForegroundColor Cyan

Test-Case '환자 로그아웃 204' 204 `
    (Invoke-Api POST '/api/bff/patient/auth/logout' (Csrf) -Session $script:PatientSession)

Test-Case '로그아웃 후 환자 API 401' 401 `
    (Invoke-Api GET '/api/bff/patient/appointments' @{} -Session $script:PatientSession) 'unauthorized'

Test-Case '직원 로그아웃 200' 200 `
    (Invoke-Api POST '/api/bff/staff/auth/logout' (Bearer $docToken))


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
    Write-Host '  docker compose logs bff --tail=150' -ForegroundColor DarkGray
    Write-Host '  docker compose logs was --tail=150' -ForegroundColor DarkGray
    exit 1
}

Write-Host ''
Write-Host '전 항목 통과. BFF 계약 검증 완료.' -ForegroundColor Green
Write-Host ''

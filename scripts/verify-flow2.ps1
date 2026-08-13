<#
.SYNOPSIS
    흐름2 (G3) 검증. 내부 직원 경로.

.DESCRIPTION
    Hybrid Toy Project - scripts/verify-flow2.ps1
    계약: README v3.1 §6.5 / §7.10 / §14 / 구축설명서 §10 · §11.2

    경로: OKD Pod -> Cloudflare Access -> Tunnel -> cloudflared -> bff-svc -> was-svc -> RDS

    여기서 처음 검증되는 것
      - Cloudflare Access Service Auth (Service Token)
      - Tunnel -> cloudflared -> bff-svc 도달
      - 직원 Bearer 흐름 (쿠키 아님)
      - 잘못된 Service Token 차단
      - X-Trace-Id 연속성

    ⚠️ 이 스크립트는 Access 뒤에서 도는 것을 전제한다.
       Service Token 이 없으면 Cloudflare 가 먼저 막아 BFF 에 도달하지 못한다.

.PARAMETER ClientId
    CF-Access-Client-Id. 생략 시 환경변수 CF_ACCESS_CLIENT_ID.

.PARAMETER ClientSecret
    CF-Access-Client-Secret. 생략 시 환경변수 CF_ACCESS_CLIENT_SECRET.

.EXAMPLE
    $env:CF_ACCESS_CLIENT_ID     = '<ID>'
    $env:CF_ACCESS_CLIENT_SECRET = '<SECRET>'
    .\verify-flow2.ps1
#>

[CmdletBinding()]
param(
    [string] $BaseUrl       = 'https://staff-api.kuspitalsoldeskproject.org',
    [string] $ClientId      = $env:CF_ACCESS_CLIENT_ID,
    [string] $ClientSecret  = $env:CF_ACCESS_CLIENT_SECRET,
    [string] $DoctorId      = 'doc_kim',
    [string] $NurseId       = 'nur_park',
    [string] $AdminId       = 'adm_choi',
    [string] $StaffPassword = '00000000'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:Pass = 0
$script:Fail = 0
$script:Results = @()


if ([string]::IsNullOrWhiteSpace($ClientId) -or [string]::IsNullOrWhiteSpace($ClientSecret)) {
    Write-Host ''
    Write-Host '[ERROR] Service Token 이 없다.' -ForegroundColor Red
    Write-Host '        리드가 Cloudflare Access 에서 발급한 값을 넣는다.'
    Write-Host ''
    Write-Host '          $env:CF_ACCESS_CLIENT_ID     = ''<ID>'''
    Write-Host '          $env:CF_ACCESS_CLIENT_SECRET = ''<SECRET>'''
    Write-Host ''
    Write-Host '        ⚠️ 값을 파일이나 커밋에 남기지 않는다.' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

# Access 헤더는 모든 요청에 붙는다. 하나라도 빠지면 Cloudflare 가 막는다.
function Access-Headers {
    return @{
        'CF-Access-Client-Id'     = $ClientId
        'CF-Access-Client-Secret' = $ClientSecret
    }
}

function Merge-Headers {
    param([hashtable] $Extra)
    $h = Access-Headers
    if ($Extra) { foreach ($k in $Extra.Keys) { $h[$k] = $Extra[$k] } }
    return $h
}


function Invoke-Api {
    param(
        [string]    $Method,
        [string]    $Path,
        [hashtable] $Headers = @{},
        [object]    $Body = $null,
        [switch]    $NoAccess          # Access 헤더를 일부러 빼는 시나리오용
    )

    $h = if ($NoAccess) { @{} } else { $Headers }

    $clean = @{}
    foreach ($k in $h.Keys) {
        if (-not [string]::IsNullOrWhiteSpace([string]$h[$k])) { $clean[$k] = $h[$k] }
    }

    $params = @{
        Method          = $Method
        Uri             = "$BaseUrl$Path"
        Headers         = $clean
        ContentType     = 'application/json; charset=utf-8'
        ErrorAction     = 'Stop'
        UseBasicParsing = $true
        TimeoutSec      = 20
        MaximumRedirection = 0          # 302 를 따라가지 않는다. 그 자체가 신호다.
    }

    if ($null -ne $Body) {
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 6 -Compress))
    }

    try {
        $res = Invoke-WebRequest @params
        return [PSCustomObject]@{
            Status      = [int]$res.StatusCode
            Body        = if ($res.Content) { try { $res.Content | ConvertFrom-Json } catch { $null } } else { $null }
            Raw         = $res.Content
            ContentType = [string]$res.Headers['Content-Type']
            TraceId     = [string]$res.Headers['X-Trace-Id']
        }
    }
    catch {
        $resp = $null
        try { if ($_.Exception.PSObject.Properties['Response']) { $resp = $_.Exception.Response } } catch { }

        if ($null -eq $resp) {
            return [PSCustomObject]@{ Status = -1; Body = $null; Raw = $_.Exception.Message
                                      ContentType = ''; TraceId = '' }
        }

        $status = if ($resp.PSObject.Properties['StatusCode'].Value -is [int]) {
                      [int]$resp.StatusCode
                  } else { [int]$resp.StatusCode.value__ }

        $ct = ''
        try { $ct = [string]$resp.ContentType } catch { }

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

        return [PSCustomObject]@{ Status = $status; Body = $parsed; Raw = $raw
                                  ContentType = $ct; TraceId = '' }
    }
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
        if ($Response.ContentType) { Write-Host "         Content-Type: $($Response.ContentType)" -ForegroundColor DarkGray }
        if ($Response.Raw) {
            $t = [string]$Response.Raw
            if ($t.Length -gt 200) { $t = $t.Substring(0, 200) + '…' }
            Write-Host "         $t" -ForegroundColor DarkGray
        }
    }
    $script:Results += [PSCustomObject]@{ Name = $Name; Ok = $ok; Detail = $detail }
}

function Bearer {
    param([string] $Token)
    return Merge-Headers @{ 'Authorization' = "Bearer $Token" }
}


# =====================================================================
Write-Host ''
Write-Host "=== 흐름2 (G3) 검증 : $BaseUrl ===" -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------------
# 1. Access 계층
#
# 🚨 여기가 §7.10 의 핵심이다.
#    Policy Action 이 Allow 면 Cloudflare 가 로그인 페이지로 302 를 보낸다.
#    Service Auth 여야 헤더 기반 인증이 성립한다.
#    401 JSON 이 오면 Access 를 통과해 BFF 까지 도달했다는 뜻이다.
# ---------------------------------------------------------------------
Write-Host '[Cloudflare Access]' -ForegroundColor Cyan

# ⚠️ Access 의 차단 응답 자체가 text/html 이다 (자체 오류 페이지).
#    로그인 폼으로의 302/200 과는 다른 것인데 최초 설계에서 이를
#    같은 것으로 오판했다 (실측 후 교정). 판정 기준은 상태코드로만 건다.
#
#    실제 구분 기준은 아래와 같다:
#      Service Auth (올바른 설정) : 토큰 없음/오류 -> 403,  올바른 토큰 -> 통과 후 401/200
#      Allow (잘못된 설정)        : 302 리다이렉트 또는 200 (로그인 폼 HTML)
$noToken = Invoke-Api GET '/api/bff/staff/patients' -NoAccess
Test-Case 'Service Token 없이 접근 차단' 403 $noToken

$probe = Invoke-Api GET '/api/bff/staff/patients' (Access-Headers)
Test-Case 'Access 통과 → BFF 도달 (401 JSON)' 401 $probe 'unauthorized' -Extra {
    param($r) $r.ContentType -match 'application/json'
}

$badToken = Invoke-Api GET '/api/bff/staff/patients' @{
    'CF-Access-Client-Id'     = $ClientId
    'CF-Access-Client-Secret' = 'wrong-secret-value-0000000000'
}
Test-Case '잘못된 Service Token → 403' 403 $badToken

# Policy 가 Allow 로 잘못 설정된 경우를 별도로 잡는다.
# 302 나 로그인 폼(HTML, 200) 이 오면 이것이 뜬다.
Test-Case 'Policy 가 Service Auth 임 (302/로그인폼 아님)' 403 $noToken -Extra {
    param($r) $r.Status -ne 200 -and $r.Status -ne 302
}

# ---------------------------------------------------------------------
# 2. 직원 인증
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '[직원 인증]' -ForegroundColor Cyan

$doc = Invoke-Api POST '/api/bff/staff/auth/login' (Access-Headers) `
    @{ login_id = $DoctorId; password = $StaffPassword }
Test-Case '의사 로그인 200 + access_token' 200 $doc `
    -Extra { param($r) $r.Body.access_token -and $r.Body.token_type -eq 'Bearer' }
Test-Case 'role = DOCTOR' 200 $doc -Extra { param($r) $r.Body.role -eq 'DOCTOR' }
Test-Case 'TTL 8시간 (expires_in 28800)' 200 $doc -Extra { param($r) $r.Body.expires_in -eq 28800 }
$docToken = if ($doc.Body) { $doc.Body.access_token } else { '' }

$nur = Invoke-Api POST '/api/bff/staff/auth/login' (Access-Headers) `
    @{ login_id = $NurseId; password = $StaffPassword }
Test-Case '간호사 로그인 200 role=NURSE' 200 $nur -Extra { param($r) $r.Body.role -eq 'NURSE' }
$nurToken = if ($nur.Body) { $nur.Body.access_token } else { '' }

$adm = Invoke-Api POST '/api/bff/staff/auth/login' (Access-Headers) `
    @{ login_id = $AdminId; password = $StaffPassword }
Test-Case '원무 로그인 200 role=ADMIN_STAFF' 200 $adm -Extra { param($r) $r.Body.role -eq 'ADMIN_STAFF' }
$admToken = if ($adm.Body) { $adm.Body.access_token } else { '' }

Test-Case '잘못된 비밀번호 401' 401 (Invoke-Api POST '/api/bff/staff/auth/login' (Access-Headers) `
    @{ login_id = $DoctorId; password = 'DefinitelyWrong!99' }) 'invalid_credentials'

# ---------------------------------------------------------------------
# 3. 인가 — 직원 토큰은 Bearer 다
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '[인가]' -ForegroundColor Cyan

Test-Case '위조 서명 Bearer 401' 401 `
    (Invoke-Api GET '/api/bff/staff/patients' (Bearer 'aaa.bbb.ccc')) 'unauthorized'

Test-Case 'DOCTOR 로 관리자 경로 403' 403 `
    (Invoke-Api GET '/api/bff/staff/admin/anything' (Bearer $docToken)) 'forbidden'

Test-Case 'NURSE 로 관리자 경로 403' 403 `
    (Invoke-Api GET '/api/bff/staff/admin/anything' (Bearer $nurToken)) 'forbidden'

# ADMIN_STAFF 는 경로 통과. 구현된 admin API 가 없으므로 404 가 정답이다.
# 403 이 나오면 권한 매핑이 틀린 것이다.
Test-Case 'ADMIN_STAFF 는 관리자 경로 통과 (404)' 404 `
    (Invoke-Api GET '/api/bff/staff/admin/anything' (Bearer $admToken))

# 🚨 위조 신원 헤더 주입 — §6.6 위조 방어 1번 원칙
Test-Case '위조 X-Actor-* 주입 401' 401 (Invoke-Api GET '/api/bff/staff/patients' `
    (Merge-Headers @{ 'X-Actor-Type' = 'STAFF'; 'X-Actor-Id' = '1'; 'X-Actor-Role' = 'ADMIN_STAFF' })) `
    'unauthorized'

# ---------------------------------------------------------------------
# 4. 진료·처방
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '[진료·처방]' -ForegroundColor Cyan

$daily = Invoke-Api GET '/api/bff/staff/patients' (Bearer $docToken)
Test-Case '당일 예약 목록 200' 200 $daily -Extra { param($r) $null -ne $r.Body }

# G2 가 만든 예약이 있으면 그것을 쓴다. 없으면 이후 시나리오는 건너뛴다.
$visitNo = $null
foreach ($a in @($daily.Body)) {
    if (-not $a.chart_written) { $visitNo = $a.visit_no; break }
}
if ($null -eq $visitNo) {
    Write-Host '         (차트 미작성 예약이 없다. 환자 예약을 먼저 만든다)' -ForegroundColor Yellow
}

Test-Case '상병코드 검색 200 (한글)' 200 `
    (Invoke-Api GET '/api/bff/staff/icd-codes?q=%EB%8B%B9%EB%87%A8' (Bearer $docToken)) `
    -Extra { param($r) @($r.Body).Count -gt 0 -and @($r.Body).Count -le 50 }

Test-Case '1자 검색 400 (WAS 본문 통과)' 400 `
    (Invoke-Api GET '/api/bff/staff/icd-codes?q=E' (Bearer $docToken)) 'validation_error'

$chartBody = @{
    visit_no = $visitNo
    icd_code = 'E1140'
    chief_complaint = 'G3 검증'
    note = 'Tunnel 경유 처방 발급'
    prescription_items = @(@{ drug_name = '메트포르민정 500mg'; dosage = '1정'
                              frequency = '1일 2회'; duration_days = 14 })
}

# 🚨 3중 방어의 최종 지점. BFF 는 경로만 보고, WAS 가 role 을 판정한다.
Test-Case 'NURSE 차트 작성 403 (WAS 최종 방어)' 403 `
    (Invoke-Api POST '/api/bff/staff/charts' (Bearer $nurToken) $chartBody) 'forbidden'

$chart = Invoke-Api POST '/api/bff/staff/charts' (Bearer $docToken) $chartBody
Test-Case 'DOCTOR 차트+처방 201' 201 $chart `
    -Extra { param($r) @($r.Body.prescription_items).Count -eq 1 }
Test-Case '상병명 스냅샷 저장' 201 $chart -Extra { param($r) $r.Body.icd_name -and $r.Body.icd_name.Length -gt 0 }

Test-Case '동일 visit_no 재발급 409' 409 `
    (Invoke-Api POST '/api/bff/staff/charts' (Bearer $docToken) $chartBody) 'duplicate_prescription'

Test-Case '차트 조회 200 + 처방 항목' 200 `
    (Invoke-Api GET "/api/bff/staff/patients/$visitNo/chart" (Bearer $docToken)) `
    -Extra { param($r) @($r.Body.prescription_items).Count -eq 1 }

Test-Case '미작성 차트 404' 404 `
    (Invoke-Api GET '/api/bff/staff/patients/V19000101-0001/chart' (Bearer $docToken)) 'not_found'

# ---------------------------------------------------------------------
# 5. 계약 형식 · 추적
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '[계약 형식 · 추적]' -ForegroundColor Cyan

$ok = Invoke-Api GET '/api/bff/staff/patients' (Bearer $docToken)
Test-Case '응답 헤더에 X-Trace-Id' 200 $ok -Extra { param($r) $r.TraceId }
Test-Case '성공 응답에 trace_id 없음' 200 $ok -Extra { param($r) $r.Raw -notmatch 'trace_id' }
Test-Case 'JSON 키가 snake_case' 200 $ok -Extra { param($r) $r.Raw -match 'visit_no' -and $r.Raw -notmatch 'visitNo' }

$err = Invoke-Api GET '/api/bff/staff/icd-codes?q=E' (Bearer $docToken)
Test-Case '오류 JSON 3필드' 400 $err -Extra {
    param($r)
    $r.Body.PSObject.Properties['error'] -and
    $r.Body.PSObject.Properties['message'] -and
    $r.Body.PSObject.Properties['trace_id']
}
if ($err.Body -and $err.Body.PSObject.Properties['trace_id']) {
    Write-Host "         (추적용 trace_id: $($err.Body.trace_id))" -ForegroundColor DarkGray
}

Test-Case '직원 로그아웃 200' 200 (Invoke-Api POST '/api/bff/staff/auth/logout' (Bearer $docToken))


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
    Write-Host '진단 순서' -ForegroundColor Yellow
    Write-Host '  302 또는 text/html   → Access Policy Action 이 Allow 다 (리드 조치)'
    Write-Host '  403 전부             → Service Token 값 오류'
    Write-Host '  502 / 504            → cloudflared 또는 bff-svc'
    Write-Host '  연결 실패            → DNS / 아웃바운드 443'
    Write-Host ''
    Write-Host '  kubectl -n app logs deploy/cloudflared --tail=50' -ForegroundColor DarkGray
    Write-Host '  kubectl -n app logs -l app=bff --tail=50' -ForegroundColor DarkGray
    exit 1
}

Write-Host ''
Write-Host '전 항목 통과. 흐름2 (G3) 검증 완료.' -ForegroundColor Green
Write-Host ''

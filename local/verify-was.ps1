<#
.SYNOPSIS
    WAS 계약 검증. 21개 시나리오.

.DESCRIPTION
    Hybrid Toy Project - local/verify-was.ps1
    계약: README v3.1 §6.5 / §6.6 / §6.7 / §6.8 / 구축설명서 §11.3

    BFF 가 아직 없으므로 WAS 내부 경로(/internal/**)를 직접 호출한다.
    BFF 가 생성하는 X-Actor-* 헤더를 이 스크립트가 대신 만든다.

    ⚠️ 이 스크립트는 BFF 의 대체물이 아니다. WAS 가 계약대로 응답하는지만 본다.
       BFF 통합 검증은 배치 3 이후 verify-flow1.ps1 이 담당한다.

.PARAMETER BaseUrl
    WAS 주소. 기본 http://localhost:18080

.EXAMPLE
    .\verify-was.ps1
#>

[CmdletBinding()]
param(
    [string] $BaseUrl = 'http://localhost:18080',
    [string] $StaffPassword = 'Local!Hospital2026'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:Pass = 0
$script:Fail = 0
$script:Results = @()


# ---------------------------------------------------------------------
# HTTP 헬퍼 - PowerShell 5.1 / 7 양쪽에서 동작한다.
#   5.1 은 -SkipHttpErrorCheck 가 없어 4xx/5xx 를 예외로 던진다.
#   양쪽 모두에서 상태코드와 본문을 얻으려면 예외를 풀어야 한다.
# ---------------------------------------------------------------------
function Invoke-Api {
    param(
        [string] $Method,
        [string] $Path,
        [hashtable] $Headers = @{},
        [object] $Body = $null
    )

    $uri = "$BaseUrl$Path"
    $params = @{
        Method      = $Method
        Uri         = $uri
        Headers     = $Headers
        ContentType = 'application/json; charset=utf-8'
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 6 -Compress
        # PowerShell 5.1 은 본문을 기본 인코딩으로 보낸다. 한글이 깨진다.
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes($json)
    }

    try {
        $res = Invoke-WebRequest @params -UseBasicParsing
        return [PSCustomObject]@{
            Status = [int]$res.StatusCode
            Body   = if ($res.Content) { $res.Content | ConvertFrom-Json } else { $null }
            Raw    = $res.Content
            Trace  = $res.Headers['X-Trace-Id']
        }
    }
    catch {
        $resp = $_.Exception.Response
        if ($null -eq $resp) {
            return [PSCustomObject]@{ Status = -1; Body = $null; Raw = $_.Exception.Message; Trace = $null }
        }

        $status = if ($resp.PSObject.Properties['StatusCode'].Value -is [int]) {
                      [int]$resp.StatusCode
                  } else {
                      [int]$resp.StatusCode.value__
                  }

        # 본문 추출 경로가 버전·상황에 따라 다르다. 둘 다 시도한다.
        #   ErrorDetails.Message : PS7 및 PS5.1 대부분
        #   ResponseStream       : ErrorDetails 가 비어 있을 때
        $raw = $null
        try {
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $raw = $_.ErrorDetails.Message
            }
        } catch { }
        if ([string]::IsNullOrWhiteSpace($raw)) {
            try {
                $stream = $resp.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                    $raw = $reader.ReadToEnd()
                    $reader.Close()
                }
            } catch { }
        }

        $parsed = $null
        if ($raw) { try { $parsed = $raw | ConvertFrom-Json } catch { } }

        return [PSCustomObject]@{ Status = $status; Body = $parsed; Raw = $raw; Trace = $null }
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
        $actual = if ($Response.Body -and $Response.Body.PSObject.Properties['error']) { $Response.Body.error } else { '(없음)' }
        $ok = ($actual -eq $ExpectError)
        $detail += " error=$actual"
    }

    if ($ok -and $Extra) {
        try   { $ok = [bool](& $Extra $Response) }
        catch { $ok = $false; $detail += " extra=예외" }
    }

    if ($ok) {
        $script:Pass++
        Write-Host ("  [PASS] {0,-46} {1}" -f $Name, $detail) -ForegroundColor Green
    }
    else {
        $script:Fail++
        Write-Host ("  [FAIL] {0,-46} {1}" -f $Name, $detail) -ForegroundColor Red
        if ($Response.Raw) { Write-Host "         본문: $($Response.Raw)" -ForegroundColor DarkGray }
    }
    $script:Results += [PSCustomObject]@{ Name = $Name; Ok = $ok; Detail = $detail }
}

function Staff-Headers {
    param([long] $Id, [string] $Role)
    return @{ 'X-Actor-Type' = 'STAFF'; 'X-Actor-Id' = "$Id"; 'X-Actor-Role' = $Role;
              'X-Trace-Id' = [guid]::NewGuid().ToString() }
}
function Patient-Headers {
    param([long] $Id)
    return @{ 'X-Actor-Type' = 'PATIENT'; 'X-Actor-Id' = "$Id"; 'X-Actor-Role' = 'PATIENT';
              'X-Trace-Id' = [guid]::NewGuid().ToString() }
}


# =====================================================================
Write-Host ''
# ---------------------------------------------------------------------
# 기동 대기
#
#   docker compose up -d 는 컨테이너 '시작' 시점에 반환한다.
#   Spring Boot 기동에는 15초 안팎이 더 걸린다. 바로 요청하면 전 항목이
#   연결 실패(-1)로 떨어지고, 애플리케이션 결함으로 오진하게 된다.
#   compose 쪽은 --wait 로, 스크립트 쪽은 여기서 막는다.
# ---------------------------------------------------------------------
function Wait-Ready {
    param([int] $TimeoutSec = 90)

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $shown = $false

    while ((Get-Date) -lt $deadline) {
        $r = Invoke-Api GET '/readyz'
        if ($r.Status -eq 200) {
            if ($shown) { Write-Host '' }
            return $true
        }
        if (-not $shown) {
            Write-Host -NoNewline '  WAS 기동 대기 중'
            $shown = $true
        }
        Write-Host -NoNewline '.'
        Start-Sleep -Seconds 2
    }

    if ($shown) { Write-Host '' }
    return $false
}

if (-not (Wait-Ready)) {
    Write-Host ''
    Write-Host "[ERROR] $BaseUrl 에 연결할 수 없다. 90초 대기 후 포기." -ForegroundColor Red
    Write-Host ''
    Write-Host '  확인 순서' -ForegroundColor Yellow
    Write-Host '    docker compose ps                  컨테이너 상태'
    Write-Host '    docker compose logs was --tail=100 기동 실패 원인'
    Write-Host '    curl.exe http://localhost:18080/readyz'
    Write-Host ''
    Write-Host '  다음부터는 --wait 로 기동 완료까지 기다린다:' -ForegroundColor Yellow
    Write-Host '    docker compose up --build -d --wait'
    Write-Host ''
    exit 1
}

Write-Host "=== WAS 계약 검증 : $BaseUrl ===" -ForegroundColor Cyan
Write-Host ''

# ---------- 헬스 ----------
Write-Host '[헬스 체크]' -ForegroundColor Cyan
Test-Case '/healthz 200'  200 (Invoke-Api GET '/healthz')
Test-Case '/readyz 200 (DB up)' 200 (Invoke-Api GET '/readyz') -Extra { param($r) $r.Body.db -eq 'up' }

# ---------- 인증 ----------
Write-Host ''
Write-Host '[인증]' -ForegroundColor Cyan

$suffix = (Get-Random -Maximum 99999)
$loginId = "pt$suffix"

$reg = Invoke-Api POST '/internal/patient/auth/register' @{} @{
    login_id = $loginId; password = 'Patient!2026'; name = '검증환자'
    birth_date = '1990-05-05'; phone = '010-0000-0000'
}
Test-Case '환자 가입 201' 201 $reg -Extra { param($r) $null -ne $r.Body.actor_id }
$patientId = if ($reg.Body) { $reg.Body.actor_id } else { 0 }

Test-Case '환자 가입 중복 409 patient_exists' 409 (Invoke-Api POST '/internal/patient/auth/register' @{} @{
    login_id = $loginId; password = 'Patient!2026'; name = '검증환자'; birth_date = '1990-05-05'
}) 'patient_exists'

Test-Case '환자 로그인 200 + 토큰 미포함' 200 (Invoke-Api POST '/internal/patient/auth/login' @{} @{
    login_id = $loginId; password = 'Patient!2026'
}) -Extra { param($r) $r.Raw -notmatch 'token' }

Test-Case '잘못된 비밀번호 401 invalid_credentials' 401 (Invoke-Api POST '/internal/patient/auth/login' @{} @{
    login_id = $loginId; password = 'WrongPassword!!'
}) 'invalid_credentials'

Test-Case '없는 계정도 동일하게 401' 401 (Invoke-Api POST '/internal/patient/auth/login' @{} @{
    login_id = 'no_such_user_zzz'; password = 'Whatever!2026'
}) 'invalid_credentials'

$docLogin = Invoke-Api POST '/internal/staff/auth/login' @{} @{ login_id = 'doc_kim'; password = $StaffPassword }
Test-Case '의사 로그인 200 role=DOCTOR' 200 $docLogin -Extra { param($r) $r.Body.role -eq 'DOCTOR' }
$doctorStaffId = if ($docLogin.Body) { $docLogin.Body.actor_id } else { 0 }

$nurLogin = Invoke-Api POST '/internal/staff/auth/login' @{} @{ login_id = 'nur_park'; password = $StaffPassword }
Test-Case '간호사 로그인 200 role=NURSE' 200 $nurLogin -Extra { param($r) $r.Body.role -eq 'NURSE' }
$nurseStaffId = if ($nurLogin.Body) { $nurLogin.Body.actor_id } else { 0 }

# ---------- 신원 헤더 2차 검증 ----------
Write-Host ''
Write-Host '[신원 헤더 2차 검증 - WAS 최종 방어선]' -ForegroundColor Cyan

Test-Case '헤더 없이 직원 API 403' 403 (Invoke-Api GET '/internal/staff/patients') 'forbidden'
Test-Case '환자 신원으로 직원 API 403' 403 (Invoke-Api GET '/internal/staff/patients' (Patient-Headers $patientId)) 'forbidden'
Test-Case '직원 신원으로 환자 API 403' 403 (Invoke-Api GET '/internal/patient/records' (Staff-Headers $doctorStaffId 'DOCTOR')) 'forbidden'
Test-Case 'DOCTOR 로 관리자 경로 403' 403 (Invoke-Api GET '/internal/staff/admin/anything' (Staff-Headers $doctorStaffId 'DOCTOR')) 'forbidden'

# ---------- 예약 ----------
Write-Host ''
Write-Host '[예약]' -ForegroundColor Cyan

$ph = Patient-Headers $patientId

$doctors = Invoke-Api GET '/internal/patient/doctors' $ph
Test-Case '의사 목록 200 (2명)' 200 $doctors -Extra { param($r) $r.Body.Count -ge 2 }
$doctorId = if ($doctors.Body) { $doctors.Body[0].doctor_id } else { 1 }
$doctorId2 = if ($doctors.Body -and $doctors.Body.Count -ge 2) { $doctors.Body[1].doctor_id } else { 2 }

$slots = Invoke-Api GET "/internal/patient/slots?doctorId=$doctorId" $ph
Test-Case '슬롯 조회 200' 200 $slots

# 계약상 예약 가능 슬롯은 미래여야 한다. 목록에 과거가 섞여 있으면 그 자체가 결함이다.
Test-Case '슬롯 목록에 과거 시각 없음' 200 $slots -Extra {
    param($r)
    if (-not $r.Body -or $r.Body.Count -eq 0) { return $false }
    $now = Get-Date
    foreach ($s in $r.Body) { if ([datetime]$s.slot_at -lt $now) { return $false } }
    return $true
}
$slotId = if ($slots.Body -and $slots.Body.Count -gt 0) { $slots.Body[0].slot_id } else { 0 }
$slotAt = if ($slots.Body -and $slots.Body.Count -gt 0) { $slots.Body[0].slot_at } else { $null }

if ($slotId -eq 0) {
    Write-Host '  [WARN] 예약 가능 슬롯이 0건이다. 오늘 진료시간(09:00~17:30)이 이미 지났을 수 있다.' -ForegroundColor Yellow
    Write-Host '         03_seed.sql 은 CURDATE() 기준 7일치를 만든다. 이후 시나리오가 연쇄 실패한다.' -ForegroundColor Yellow
}

$book = Invoke-Api POST '/internal/patient/appointments' $ph @{ slot_id = $slotId; symptom = '두통' }
Test-Case '예약 201 + visit_no 발급' 201 $book -Extra { param($r) $r.Body.visit_no -match '^V\d{8}-\d{4}$' }
$visitNo = if ($book.Body) { $book.Body.visit_no } else { $null }

Test-Case '예약 응답 status=BOOKED (대문자)' 201 $book -Extra { param($r) $r.Body.status -eq 'BOOKED' }

# 다른 환자로 같은 슬롯
$other = Invoke-Api POST '/internal/patient/auth/register' @{} @{
    login_id = "px$suffix"; password = 'Patient!2026'; name = '타환자'; birth_date = '1985-03-03'
}
$otherId = if ($other.Body) { $other.Body.actor_id } else { 0 }
Test-Case '같은 슬롯 타 환자 409 slot_taken' 409 (Invoke-Api POST '/internal/patient/appointments' (Patient-Headers $otherId) @{
    slot_id = $slotId
}) 'slot_taken'

# 같은 환자, 같은 시각, 다른 의사
$slots2 = Invoke-Api GET "/internal/patient/slots?doctorId=$doctorId2" $ph
$sameTimeSlot = 0
if ($slots2.Body) {
    foreach ($s in $slots2.Body) { if ($s.slot_at -eq $slotAt) { $sameTimeSlot = $s.slot_id; break } }
}
Test-Case '같은 시각 타 의사 409 duplicate_booking' 409 (Invoke-Api POST '/internal/patient/appointments' $ph @{
    slot_id = $sameTimeSlot
}) 'duplicate_booking'

# ---------- 상병코드 ----------
Write-Host ''
Write-Host '[상병코드 검색]' -ForegroundColor Cyan

$dh = Staff-Headers $doctorStaffId 'DOCTOR'

Test-Case '1자 검색 400 validation_error' 400 (Invoke-Api GET '/internal/staff/icd-codes?q=E' $dh) 'validation_error'
$icd = Invoke-Api GET '/internal/staff/icd-codes?q=%EB%8B%B9%EB%87%A8' $dh   # q=당뇨
Test-Case '명칭 검색 200 + 50건 이하' 200 $icd -Extra { param($r) $r.Body.Count -gt 0 -and $r.Body.Count -le 50 }
Test-Case '코드 prefix 검색 200' 200 (Invoke-Api GET '/internal/staff/icd-codes?q=E11' $dh) -Extra { param($r) $r.Body.Count -gt 0 }

# ---------- 진료·처방 ----------
Write-Host ''
Write-Host '[진료·처방]' -ForegroundColor Cyan

$sh = Staff-Headers $doctorStaffId 'DOCTOR'
$nh = Staff-Headers $nurseStaffId 'NURSE'

$chartBody = @{
    visit_no = $visitNo
    icd_code = 'E1140'
    chief_complaint = '다뇨, 하지 저림'
    note = '혈당 조절 불량. 2주 후 재내원.'
    prescription_items = @(
        @{ drug_name = '메트포르민정 500mg'; dosage = '1정'; frequency = '1일 2회'; duration_days = 14 }
    )
}

Test-Case 'NURSE 차트 작성 403' 403 (Invoke-Api POST '/internal/staff/charts' $nh $chartBody) 'forbidden'

Test-Case '없는 상병코드 400 validation_error' 400 (Invoke-Api POST '/internal/staff/charts' $sh @{
    visit_no = $visitNo; icd_code = 'ZZZ99'; prescription_items = @()
}) 'validation_error'

$chart = Invoke-Api POST '/internal/staff/charts' $sh $chartBody
Test-Case 'DOCTOR 차트+처방 201' 201 $chart -Extra { param($r) $r.Body.prescription_items.Count -eq 1 }
Test-Case '상병명 스냅샷 저장됨' 201 $chart -Extra { param($r) $r.Body.icd_name -and $r.Body.icd_name.Length -gt 0 }

Test-Case '동일 visit_no 재발급 409' 409 (Invoke-Api POST '/internal/staff/charts' $sh $chartBody) 'duplicate_prescription'

Test-Case '차트 조회 200 + 처방 항목' 200 (Invoke-Api GET "/internal/staff/patients/$visitNo/chart" $sh) `
    -Extra { param($r) $r.Body.prescription_items.Count -eq 1 }

Test-Case '미작성 차트 404' 404 (Invoke-Api GET '/internal/staff/patients/V19000101-0001/chart' $sh) 'not_found'

$daily = Invoke-Api GET '/internal/staff/patients' $sh
Test-Case '당일 예약 목록 200' 200 $daily -Extra { param($r) $r.Body.Count -ge 1 }

# ---------- 환자 조회 ----------
Write-Host ''
Write-Host '[환자 본인 조회]' -ForegroundColor Cyan

Test-Case '본인 처방전 200 (1건)' 200 (Invoke-Api GET '/internal/patient/prescriptions' $ph) `
    -Extra { param($r) $r.Body.Count -eq 1 }

Test-Case '타 환자 처방전 조회 0건' 200 (Invoke-Api GET '/internal/patient/prescriptions' (Patient-Headers $otherId)) `
    -Extra { param($r) $r.Body.Count -eq 0 }

# ---------- 계약 형식 ----------
Write-Host ''
Write-Host '[계약 형식]' -ForegroundColor Cyan

$err = Invoke-Api GET '/internal/staff/icd-codes?q=E' $sh
Test-Case '오류 JSON 3필드 (error/message/trace_id)' 400 $err -Extra {
    param($r)
    $r.Body.PSObject.Properties['error'] -and
    $r.Body.PSObject.Properties['message'] -and
    $r.Body.PSObject.Properties['trace_id']
}

Test-Case '성공 응답에 trace_id 없음' 200 (Invoke-Api GET '/internal/patient/doctors' $ph) `
    -Extra { param($r) $r.Raw -notmatch 'trace_id' }

Test-Case 'JSON 키가 snake_case' 200 (Invoke-Api GET '/internal/patient/appointments' $ph) `
    -Extra { param($r) $r.Raw -match 'visit_no' -and $r.Raw -notmatch 'visitNo' }


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
    Write-Host 'WAS 로그 확인: docker compose logs was --tail=100' -ForegroundColor DarkGray
    exit 1
}

Write-Host ''
Write-Host '전 항목 통과. WAS 계약 검증 완료.' -ForegroundColor Green
Write-Host ''

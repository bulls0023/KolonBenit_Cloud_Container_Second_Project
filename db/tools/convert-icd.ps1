<#
.SYNOPSIS
    공공데이터 KCD 상병코드 JSON -> 04_icd_seed.sql 변환기.

.DESCRIPTION
    Hybrid Toy Project - db/tools/convert-icd.ps1
    계약: README v3.1 §6.10 (공공데이터 적재 계약)

    이 스크립트는 오프라인 도구다. AWS 나 RDS 에 접속하지 않는다.
    산출된 SQL 은 git 에 커밋한 뒤 DB팀이 admin 권한으로 실행한다.

    [A안 필터]  완전코드구분 <> 'N'  AND  주상병사용구분 <> 'N'
      원본에서 'N' 은 배제 신호다. 정상값은 빈 문자열이다.
      '= Y' 로 필터하면 0건이 된다. 원본에 'Y' 값 자체가 없다.

    [2테이블 분리]
      원본은 한 상병기호에 명칭이 여러 건 달린 동의어 색인이다.
      E1140 하나에 60건이 존재한다. 단일 테이블에 전량 INSERT 하면
      PRIMARY KEY 위반으로 적재가 실패한다.
        icd_code          첫 등장 레코드 = 대표명 (KCD 공표 순서)
        icd_code_synonym  전 레코드 (대표명 포함). 검색 대상

    [DELETE 를 쓰지 않는 이유]
      chart.icd_code 가 ON DELETE RESTRICT 로 마스터를 참조한다.
      진료 기록이 하나라도 있으면 DELETE FROM icd_code 는 FK 위반으로 실패한다.
      마스터는 UPSERT, 동의어는 TRUNCATE 후 재적재한다.

.PARAMETER InputPath
    원본 JSON. 기본 .\raw\data.json

.PARAMETER OutputPath
    산출 SQL. 기본 .\04_icd_seed.sql

.PARAMETER BatchSize
    INSERT 한 문장당 행 수. 기본 1000.
    단건 INSERT 37,543회는 수 분이 걸린다. 배치는 선택이 아니다.

.EXAMPLE
    cd db
    .\tools\convert-icd.ps1

.EXAMPLE
    .\tools\convert-icd.ps1 -InputPath .\raw\data_2027.json -OutputPath .\04_icd_seed.sql
    KCD 개정본으로 재생성한다.
#>

[CmdletBinding()]
param(
    [string] $InputPath  = '.\raw\data.json',
    [string] $OutputPath = '.\04_icd_seed.sql',

    [ValidateRange(100, 5000)]
    [int]    $BatchSize  = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 기대 산출 건수. 원본이 바뀌면 달라지지만, 같은 원본이면 반드시 이 값이어야 한다.
$EXPECT_MASTER  = 14283
$EXPECT_SYNONYM = 37543


# ---------------------------------------------------------------------
# SQL 리터럴 변환
# ---------------------------------------------------------------------
# JavaScriptSerializer 경로에서는 Dictionary 가 돌아온다. 접근 방식을 통일한다.
function Get-Field {
    param([object] $Row, [string] $Name)

    if ($Row -is [System.Collections.IDictionary]) {
        if ($Row.Contains($Name)) { return $Row[$Name] }
        return $null
    }

    return $Row.$Name
}


function ConvertTo-SqlString {
    param([object] $Value)

    if ($null -eq $Value) { return 'NULL' }

    $s = ([string]$Value).Trim()
    if ($s -eq '') { return 'NULL' }

    # MySQL 기본 모드에서 백슬래시는 이스케이프 문자다. 둘 다 처리한다.
    # (실측: 이 데이터셋에 백슬래시 0건, 작은따옴표 5건)
    $s = $s.Replace('\', '\\').Replace("'", "''")

    return "'" + $s + "'"
}

function ConvertTo-SqlNumber {
    param([object] $Value)

    if ($null -eq $Value) { return 'NULL' }

    $s = ([string]$Value).Trim()
    if ($s -match '^\d+$') { return $s }

    return 'NULL'
}


# ---------------------------------------------------------------------
# JSON 파싱
#
#   Windows PowerShell 5.1 의 ConvertFrom-Json 은 내부적으로
#   JavaScriptSerializer 를 쓰며, 환경에 따라 maxJsonLength 제한에 걸린다:
#     "The length of the string exceeds the value set on the maxJsonLength property"
#   19MB 원본은 이 제한에 걸릴 수 있으므로 실패 시 직접 직렬화기를 쓴다.
#
#   ⚠️ PS 5.1 에서는 47,798개 객체 생성에 수십 초 ~ 수 분이 걸린다.
#      PowerShell 7 (pwsh) 로 실행하면 훨씬 빠르다.
# ---------------------------------------------------------------------
function ConvertFrom-LargeJson {
    param([string] $Text)

    try {
        return ($Text | ConvertFrom-Json)
    }
    catch {
        Write-Host '[INFO  ] ConvertFrom-Json 실패. JavaScriptSerializer 로 재시도한다.' -ForegroundColor DarkGray

        Add-Type -AssemblyName System.Web.Extensions
        $ser = [System.Web.Script.Serialization.JavaScriptSerializer]::new()
        $ser.MaxJsonLength      = [int]::MaxValue
        $ser.RecursionLimit     = 256

        return $ser.DeserializeObject($Text)
    }
}


# =====================================================================
# 1. 읽기
# =====================================================================
if (-not (Test-Path -LiteralPath $InputPath)) {
    Write-Host "[ERROR] 원본을 찾을 수 없다: $InputPath" -ForegroundColor Red
    Write-Host '        db/raw/data.json 위치를 확인한다.'
    exit 1
}

$sizeMb = [math]::Round((Get-Item -LiteralPath $InputPath).Length / 1MB, 1)
Write-Host "[READ  ] $InputPath ($sizeMb MB)" -ForegroundColor DarkGray

# ConvertFrom-Json 은 Windows PowerShell 5.1 에서 47,798개 객체를 파싱하는 데
# 수십 초 ~ 수 분이 걸린다. PowerShell 7+ 는 훨씬 빠르다.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host '[INFO  ] Windows PowerShell 5.1 감지. 파싱에 시간이 걸린다 (수십 초).' -ForegroundColor DarkGray
    Write-Host '         PowerShell 7 이 설치되어 있으면 pwsh 로 실행하는 편이 빠르다.' -ForegroundColor DarkGray
}

$json = Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8
$rows = ConvertFrom-LargeJson -Text $json
$json = $null

$total = $rows.Count
Write-Host "[READ  ] $total rows"


# =====================================================================
# 2. A안 필터
# =====================================================================
$kept = [System.Collections.Generic.List[object]]::new()

foreach ($r in $rows) {
    $full = ([string](Get-Field $r '완전코드구분')).Trim()
    $main = ([string](Get-Field $r '주상병사용구분')).Trim()

    if ($full -ne 'N' -and $main -ne 'N') {
        $kept.Add($r)
    }
}

$rows     = $null
$excluded = $total - $kept.Count

Write-Host "[FILTER] excluded $excluded  (완전코드구분='N' or 주상병사용구분='N')"

if ($kept.Count -eq 0) {
    Write-Host ''
    Write-Host '[ERROR] 적재 대상이 0건이다. 필터가 반전되었을 가능성이 높다.' -ForegroundColor Red
    Write-Host "        원본에 'Y' 값은 존재하지 않는다. 정상값은 빈 문자열이다." -ForegroundColor Red
    exit 1
}


# =====================================================================
# 3. 마스터 추출 - 상병기호별 첫 등장 레코드
# =====================================================================
$seen   = [System.Collections.Generic.HashSet[string]]::new()
$master = [System.Collections.Generic.List[object]]::new()

foreach ($r in $kept) {
    $code = ([string](Get-Field $r '상병기호')).Trim()

    if ($code -ne '' -and $seen.Add($code)) {
        $master.Add($r)
    }
}

Write-Host "[MASTER] icd_code          $($master.Count)"
Write-Host "[SYNONYM] icd_code_synonym $($kept.Count)"


# =====================================================================
# 4. 쓰기
#    Add-Content 를 반복 호출하면 매번 파일을 열고 닫아 O(n^2) 가 된다.
#    StreamWriter 로 한 번만 연다.
#    UTF8Encoding($false) = BOM 없음. BOM 이 붙으면 MySQL 이 첫 구문을 깨뜨린다.
# =====================================================================
$outFull  = [System.IO.Path]::GetFullPath(
              [System.IO.Path]::Combine((Get-Location).Path, $OutputPath))
$encoding = [System.Text.UTF8Encoding]::new($false)
$w        = [System.IO.StreamWriter]::new($outFull, $false, $encoding)

try {
    $w.Write("-- =====================================================================`n")
    $w.Write("-- Hybrid Toy Project - 04_icd_seed.sql  (자동 생성물. 직접 편집 금지)`n")
    $w.Write("-- 생성기 : db/tools/convert-icd.ps1`n")
    $w.Write("-- 원본   : $InputPath`n")
    $w.Write("-- 계약   : README v3.1 §6.10`n")
    $w.Write("-- 요구   : MySQL 8.0.19 이상 (INSERT ... AS alias 구문)`n")
    $w.Write("-- ---------------------------------------------------------------------`n")
    $w.Write("-- 원본 $total 행 / 제외 $excluded 행 / 마스터 $($master.Count) 행 / 동의어 $($kept.Count) 행`n")
    $w.Write("-- =====================================================================`n`n")
    $w.Write("USE commondb;`n`n")
    $w.Write("SET NAMES utf8mb4;`n")
    $w.Write("SET autocommit = 0;`n")
    $w.Write("SET unique_checks = 0;`n")
    $w.Write("SET foreign_key_checks = 0;`n`n")
    $w.Write("-- 동의어는 전량 교체한다. 참조하는 테이블이 없으므로 TRUNCATE 가 안전하다.`n")
    $w.Write("TRUNCATE TABLE icd_code_synonym;`n`n")

    # --- 4.1 마스터 UPSERT ---
    $w.Write("-- ---------------------------------------------------------------------`n")
    $w.Write("-- 1. icd_code - 마스터 $($master.Count) 행 (UPSERT)`n")
    $w.Write("--`n")
    $w.Write("--    DELETE 하지 않는다. chart.icd_code 가 ON DELETE RESTRICT 로 참조하므로`n")
    $w.Write("--    진료 기록이 하나라도 있으면 DELETE 는 FK 위반으로 실패한다.`n")
    $w.Write("--    KCD 개정본 재적재는 UPSERT 로 처리한다.`n")
    $w.Write("-- ---------------------------------------------------------------------`n")

    for ($i = 0; $i -lt $master.Count; $i += $BatchSize) {

        $end = [math]::Min($i + $BatchSize, $master.Count) - 1
        $sb  = [System.Text.StringBuilder]::new()

        [void]$sb.Append("INSERT INTO icd_code (code,name_kr,name_en,gender_restriction," +
                         "age_min,age_max,infectious_class,oriental_medicine) VALUES`n")

        for ($j = $i; $j -le $end; $j++) {
            $r = $master[$j]

            [void]$sb.Append('(')
            [void]$sb.Append((ConvertTo-SqlString (Get-Field $r '상병기호')));       [void]$sb.Append(',')
            [void]$sb.Append((ConvertTo-SqlString (Get-Field $r '한글명')));         [void]$sb.Append(',')
            [void]$sb.Append((ConvertTo-SqlString (Get-Field $r '영문명')));         [void]$sb.Append(',')
            [void]$sb.Append((ConvertTo-SqlString (Get-Field $r '성별구분')));       [void]$sb.Append(',')
            [void]$sb.Append((ConvertTo-SqlNumber (Get-Field $r '하한연령')));       [void]$sb.Append(',')
            [void]$sb.Append((ConvertTo-SqlNumber (Get-Field $r '상한연령')));       [void]$sb.Append(',')
            [void]$sb.Append((ConvertTo-SqlString (Get-Field $r '법정감염병구분'))); [void]$sb.Append(',')
            [void]$sb.Append((ConvertTo-SqlString (Get-Field $r '양한방구분')))
            [void]$sb.Append(')')

            if ($j -lt $end) { [void]$sb.Append(",`n") }
        }

        [void]$sb.Append("`nAS new ON DUPLICATE KEY UPDATE`n")
        [void]$sb.Append("  name_kr=new.name_kr, name_en=new.name_en,`n")
        [void]$sb.Append("  gender_restriction=new.gender_restriction,`n")
        [void]$sb.Append("  age_min=new.age_min, age_max=new.age_max,`n")
        [void]$sb.Append("  infectious_class=new.infectious_class,`n")
        [void]$sb.Append("  oriental_medicine=new.oriental_medicine;`n`n")

        $w.Write($sb.ToString())
    }

    # --- 4.2 동의어 INSERT ---
    $w.Write("-- ---------------------------------------------------------------------`n")
    $w.Write("-- 2. icd_code_synonym - 동의어 $($kept.Count) 행`n")
    $w.Write("--    대표명도 포함한다. 검색은 이 테이블만 보면 되므로 UNION 이 불필요하다.`n")
    $w.Write("-- ---------------------------------------------------------------------`n")

    for ($i = 0; $i -lt $kept.Count; $i += $BatchSize) {

        $end = [math]::Min($i + $BatchSize, $kept.Count) - 1
        $sb  = [System.Text.StringBuilder]::new()

        [void]$sb.Append("INSERT INTO icd_code_synonym (code,name_kr,name_en) VALUES`n")

        for ($j = $i; $j -le $end; $j++) {
            $r = $kept[$j]

            [void]$sb.Append('(')
            [void]$sb.Append((ConvertTo-SqlString (Get-Field $r '상병기호'))); [void]$sb.Append(',')
            [void]$sb.Append((ConvertTo-SqlString (Get-Field $r '한글명')));   [void]$sb.Append(',')
            [void]$sb.Append((ConvertTo-SqlString (Get-Field $r '영문명')))
            [void]$sb.Append(')')

            if ($j -lt $end) { [void]$sb.Append(",`n") }
        }

        [void]$sb.Append(";`n`n")
        $w.Write($sb.ToString())
    }

    $w.Write("SET foreign_key_checks = 1;`n")
    $w.Write("SET unique_checks = 1;`n")
    $w.Write("COMMIT;`n")
    $w.Write("SET autocommit = 1;`n`n")

    $w.Write("-- ---------------------------------------------------------------------`n")
    $w.Write("-- 3. 옵티마이저 통계 갱신 - 생략하면 검색이 느려진다`n")
    $w.Write("--`n")
    $w.Write("--    대량 적재 직후 InnoDB 의 행수 추정치는 실제와 크게 다르다.`n")
    $w.Write("--    실측: ANALYZE 전 icd_code=3행 / icd_code_synonym=2행 으로 인식.`n")
    $w.Write("--    이 상태에서는 옵티마이저가 인덱스를 버리고 풀스캔을 고른다.`n")
    $w.Write("-- ---------------------------------------------------------------------`n")
    $w.Write("ANALYZE TABLE icd_code, icd_code_synonym;`n`n")

    $w.Write("-- =====================================================================`n")
    $w.Write("-- 검증`n")
    $w.Write("-- =====================================================================`n")
    $w.Write("-- SELECT COUNT(*) FROM icd_code;                              -- $($master.Count)`n")
    $w.Write("-- SELECT COUNT(*) FROM icd_code_synonym;                      -- $($kept.Count)`n")
    $w.Write("-- SELECT COUNT(*) FROM icd_code_synonym WHERE code='E1140';   -- 60`n")
    $w.Write("-- SELECT name_kr FROM icd_code WHERE code='E1140';            -- 한글 정상`n")
    $w.Write("-- SELECT COUNT(*) FROM icd_code_synonym s`n")
    $w.Write("--   LEFT JOIN icd_code m ON m.code=s.code WHERE m.code IS NULL;  -- 0 (고아 없음)`n")
}
finally {
    $w.Flush()
    $w.Close()
    $w.Dispose()
}

$outMb = [math]::Round((Get-Item -LiteralPath $outFull).Length / 1MB, 1)
Write-Host "[WRITE ] $OutputPath ($outMb MB, UTF-8 no BOM)"


# =====================================================================
# 5. 자기 검증 - 예상 건수와 다르면 경고한다
# =====================================================================
$mismatch = $false

if ($master.Count -ne $EXPECT_MASTER)   { $mismatch = $true }
if ($kept.Count   -ne $EXPECT_SYNONYM)  { $mismatch = $true }

Write-Host ''

if ($mismatch) {
    Write-Host '[WARN  ] 건수가 기준값과 다르다.' -ForegroundColor Yellow
    Write-Host "         기대: 마스터 $EXPECT_MASTER / 동의어 $EXPECT_SYNONYM"
    Write-Host "         실제: 마스터 $($master.Count) / 동의어 $($kept.Count)"
    Write-Host '         KCD 개정본을 쓴 경우라면 정상이다. 이 경우 README §6.10 의'
    Write-Host '         건수와 게이트 D2 기준값을 함께 갱신한다.' -ForegroundColor Yellow
}
else {
    Write-Host '[OK    ] 건수가 기준값과 일치한다.' -ForegroundColor Green
}

Write-Host ''
Write-Host '다음 단계' -ForegroundColor Cyan
Write-Host "  1. git 커밋      : git add $OutputPath && git commit -m 'db: ICD seed'"
Write-Host '  2. 파드로 전달   : kubectl -n app cp .\04_icd_seed.sql mysql-cli:/tmp/'
Write-Host '  3. 적재 후 게이트 D2 검증 (구축설명서 §5.1)'
Write-Host ''

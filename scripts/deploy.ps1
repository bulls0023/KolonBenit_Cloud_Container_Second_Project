<#
.SYNOPSIS
    ECR 빌드·푸시 및 EKS 배포.

.DESCRIPTION
    Hybrid Toy Project - scripts/deploy.ps1
    계약: README v3.1 §11.2 / §11.3 / §16-4

    ⚠️ ECR 은 immutable tag 다. 같은 태그를 두 번 푸시할 수 없다.
       태그는 git short SHA 이므로, 커밋하지 않은 수정은 이전 태그를 재사용하게
       되어 푸시가 거부된다. 반드시 커밋 후 실행한다.

    ⚠️ --platform linux/amd64 는 생략할 수 없다.
       EKS 노드는 amd64 다. ARM 이미지를 올리면 파드가 exec format error 로
       CrashLoopBackOff 에 빠지고, 로그에 원인이 거의 남지 않는다.

.PARAMETER Service
    was | bff | patient-web | all

.PARAMETER Action
    build | apply | all

.PARAMETER SkipDirtyCheck
    커밋되지 않은 변경이 있어도 진행한다. 권장하지 않는다.

.EXAMPLE
    .\deploy.ps1 -Service was -Action all
#>

[CmdletBinding()]
param(
    [ValidateSet('was', 'bff', 'patient-web', 'all')]
    [string] $Service = 'all',

    [ValidateSet('build', 'apply', 'all')]
    [string] $Action = 'all',

    [switch] $SkipDirtyCheck
)

Set-StrictMode -Version Latest

# ⚠️ 'Stop' 을 쓰지 않는다.
#    이 스크립트는 aws / docker / kubectl 네이티브 명령이 대부분이다.
#    'Stop' 에서는 이들이 stderr 에 한 줄만 써도 NativeCommandError 로
#    스크립트가 죽는다. 실패가 아닌 정보 출력에도 죽는다 (실측).
#    성공/실패 판정은 전부 $LASTEXITCODE 로 명시한다.
$ErrorActionPreference = 'Continue'

$ACCOUNT  = '597106152264'
$REGION   = 'ap-northeast-2'
$REGISTRY = "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
$NS       = 'app'

$root   = Split-Path -Parent $PSScriptRoot
$k8sDir = Join-Path $root 'k8s'

# 서비스 -> 빌드 컨텍스트
$CONTEXTS = @{
    'was'         = (Join-Path $root 'apps\was')
    'bff'         = (Join-Path $root 'apps\bff')
    'patient-web' = (Join-Path $root 'apps\patient-web')
}


function Assert-Prerequisite {

    foreach ($cmd in @('docker', 'kubectl', 'aws', 'git')) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            Write-Host "[ERROR] $cmd 를 찾을 수 없다." -ForegroundColor Red
            exit 1
        }
    }

    # 위와 같은 이유로 전 구간에서 네이티브 stderr 를 오류로 승격시키지 않는다.
    # 판정은 전부 $LASTEXITCODE 로 한다.
    $ErrorActionPreference = 'Continue'

    $ident = aws sts get-caller-identity --output json 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[ERROR] AWS 자격증명이 없다. aws configure 를 확인한다.' -ForegroundColor Red
        exit 1
    }
    if ($ident.Account -ne $ACCOUNT) {
        Write-Host "[ERROR] AWS 계정이 다르다: $($ident.Account) (기대 $ACCOUNT)" -ForegroundColor Red
        exit 1
    }
    Write-Host "  AWS   : $($ident.Arn)"

    $ctx = kubectl config current-context 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[ERROR] kubectl 컨텍스트가 없다.' -ForegroundColor Red
        Write-Host "        aws eks update-kubeconfig --name hybrid-toy-eks --region $REGION"
        exit 1
    }
    # 엉뚱한 클러스터에 배포하는 사고를 막는다.
    if ($ctx -notmatch 'hybrid-toy-eks') {
        Write-Host "[ERROR] kubectl 컨텍스트가 hybrid-toy-eks 가 아니다: $ctx" -ForegroundColor Red
        exit 1
    }
    Write-Host "  k8s   : $ctx"
}


function Get-ImageTag {

    Push-Location $root
    try {
        $tag = (git rev-parse --short HEAD).Trim()
        $dirty = git status --porcelain

        if ($dirty -and -not $SkipDirtyCheck) {
            Write-Host ''
            Write-Host '[ERROR] 커밋되지 않은 변경이 있다.' -ForegroundColor Red
            Write-Host '        태그는 git SHA 이므로, 지금 빌드하면 이미지 내용과'
            Write-Host '        태그가 가리키는 커밋이 달라진다. 추적이 불가능해진다.'
            Write-Host ''
            $dirty | Select-Object -First 10 | ForEach-Object { Write-Host "          $_" }
            Write-Host ''
            Write-Host '        커밋 후 재실행하거나 -SkipDirtyCheck 를 쓴다.' -ForegroundColor Yellow
            exit 1
        }
        return $tag
    }
    finally { Pop-Location }
}


function Invoke-BuildPush {
    param([string] $Svc, [string] $Tag)

    $ctx = $CONTEXTS[$Svc]
    if (-not (Test-Path (Join-Path $ctx 'Dockerfile'))) {
        Write-Host "[SKIP ] $Svc : Dockerfile 이 없다 ($ctx)" -ForegroundColor DarkGray
        return $false
    }

    $image = "$REGISTRY/hybrid-toy/${Svc}:$Tag"

    # immutable tag 다. 이미 있으면 빌드 자체를 건너뛴다.
    #
    # ⚠️ ErrorActionPreference='Stop' 에서는 네이티브 명령이 stderr 에 쓰기만 해도
    #    NativeCommandError 로 승격되어 스크립트가 죽는다.
    #    ecr describe-images 는 "이미지 없음"을 stderr 로 알린다 - 정상 경로다.
    #    이 블록에서만 Continue 로 낮추고 종료코드로 판정한다.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        aws ecr describe-images --repository-name "hybrid-toy/$Svc" `
            --image-ids imageTag=$Tag --region $REGION 2>&1 | Out-Null
        $exists = ($LASTEXITCODE -eq 0)
    }
    finally { $ErrorActionPreference = $prev }

    if ($exists) {
        Write-Host "[SKIP ] $Svc : $Tag 태그가 이미 ECR 에 있다 (immutable)" -ForegroundColor Yellow
        return $true
    }

    Write-Host "[BUILD] $image" -ForegroundColor Cyan
    docker build --platform linux/amd64 -t $image $ctx
    if ($LASTEXITCODE -ne 0) { Write-Host '[ERROR] 빌드 실패' -ForegroundColor Red; exit 1 }

    # 아키텍처 검증. --platform 이 무시되는 환경이 있다.
    $arch = docker image inspect $image --format '{{.Os}}/{{.Architecture}}'
    if ($arch -ne 'linux/amd64') {
        Write-Host "[ERROR] 이미지 아키텍처가 $arch 다. EKS 노드는 amd64 다." -ForegroundColor Red
        Write-Host '        푸시하지 않는다. 푸시하면 그 태그는 영구 소모된다.' -ForegroundColor Red
        exit 1
    }
    Write-Host "        arch = $arch"

    Write-Host "[PUSH ] $image" -ForegroundColor Cyan
    docker push $image
    if ($LASTEXITCODE -ne 0) { Write-Host '[ERROR] 푸시 실패' -ForegroundColor Red; exit 1 }

    return $true
}


function Invoke-Apply {
    param([string] $Svc, [string] $Tag)

    $dir = Join-Path $k8sDir $Svc
    if (-not (Test-Path $dir)) {
        Write-Host "[SKIP ] $Svc : 매니페스트 디렉토리 없음" -ForegroundColor DarkGray
        return
    }

    # 자리표시자를 치환한 임시본으로 적용한다. 원본은 커밋 상태를 유지한다.
    $tmp = Join-Path $env:TEMP "k8s-$Svc-$Tag"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Path $tmp | Out-Null

    foreach ($f in Get-ChildItem $dir -Filter '*.yaml') {

        # *.secret.example.yaml 은 적용 대상이 아니다 (§11.0)
        if ($f.Name -like '*secret.example*') { continue }

        $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
        $text = $text.Replace('__TAG__', $Tag)
        [System.IO.File]::WriteAllText((Join-Path $tmp $f.Name), $text,
            (New-Object System.Text.UTF8Encoding $false))
    }

    # 치환 누락 검사. __TAG__ 가 남은 채 apply 하면 ImagePullBackOff 가 난다.
    $left = Select-String -Path (Join-Path $tmp '*.yaml') -Pattern '__[A-Z_]+__' -List
    if ($left) {
        Write-Host "[ERROR] $Svc : 치환되지 않은 자리표시자" -ForegroundColor Red
        $left | ForEach-Object { Write-Host "          $($_.Filename): $($_.Matches[0].Value)" }
        Write-Host '        ACM ARN / cloudflared digest 는 수동 치환 대상이다.' -ForegroundColor Yellow
        exit 1
    }

    Write-Host "[APPLY] $Svc" -ForegroundColor Cyan

    # ⚠️ --force-conflicts 가 필요한 이유
    #    이전에 client-side apply(kubectl apply -f) 로 만든 리소스는
    #    필드 소유권이 'kubectl-client-side-apply' 에 남는다.
    #    server-side apply 는 그 필드를 건드릴 때 충돌로 거부한다.
    #    이 매니페스트가 단일 권위이므로 소유권을 인수하는 것이 옳다.
    #    (삭제가 아니라 소유권 이전이다. 파드는 롤링으로 교체된다.)
    kubectl apply --server-side --force-conflicts -f $tmp
    if ($LASTEXITCODE -ne 0) { exit 1 }

    Remove-Item -Recurse -Force $tmp

    # 롤아웃 완료까지 기다린다. 여기서 실패하면 다음 서비스를 배포하지 않는다.
    Write-Host "[WAIT ] $Svc 롤아웃 (최대 5분)" -ForegroundColor DarkGray
    kubectl -n $NS rollout status deploy/$Svc --timeout=300s
    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host "[ERROR] $Svc 롤아웃 실패" -ForegroundColor Red
        Write-Host "        kubectl -n $NS get pod -l app=$Svc"
        Write-Host "        kubectl -n $NS describe pod -l app=$Svc"
        Write-Host "        kubectl -n $NS logs -l app=$Svc --tail=100"
        exit 1
    }
}


# =====================================================================
Write-Host ''
Write-Host '=== 사전 점검 ===' -ForegroundColor Cyan
Assert-Prerequisite

$tag = Get-ImageTag
Write-Host "  tag   : $tag"

# 배포 순서는 의존 역순이다: WAS -> BFF -> Web (§11.3)
$targets = if ($Service -eq 'all') { @('was', 'bff', 'patient-web') } else { @($Service) }

if ($Action -in @('build', 'all')) {
    Write-Host ''
    Write-Host '=== ECR 로그인 ===' -ForegroundColor Cyan
    aws ecr get-login-password --region $REGION |
        docker login --username AWS --password-stdin $REGISTRY
    if ($LASTEXITCODE -ne 0) { exit 1 }

    Write-Host ''
    Write-Host '=== 빌드 · 푸시 ===' -ForegroundColor Cyan
    foreach ($s in $targets) { Invoke-BuildPush -Svc $s -Tag $tag | Out-Null }
}

if ($Action -in @('apply', 'all')) {
    Write-Host ''
    Write-Host '=== 배포 ===' -ForegroundColor Cyan
    foreach ($s in $targets) { Invoke-Apply -Svc $s -Tag $tag }
}

Write-Host ''
Write-Host '=== 완료 ===' -ForegroundColor Green
kubectl -n $NS get pod -o wide
Write-Host ''
Write-Host "이미지 태그: $tag" -ForegroundColor Cyan
Write-Host 'README §21 배포 기록에 태그를 남긴다.' -ForegroundColor DarkGray
Write-Host ''

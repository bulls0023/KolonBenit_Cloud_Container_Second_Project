<#
.SYNOPSIS
    배포 전 클러스터·시크릿 점검. 배포하지 않는다.

.DESCRIPTION
    Hybrid Toy Project - scripts/preflight.ps1

    파드가 CrashLoopBackOff 로 돌기 시작하면 원인이 코드인지 설정인지
    구분하기 어려워진다. 그 전에 확인할 수 있는 것을 전부 확인한다.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$NS = 'app'
$pass = 0
$fail = 0

function Check {
    param([string] $Name, [scriptblock] $Test, [string] $Hint = '')
    try   { $ok = [bool](& $Test) }
    catch { $ok = $false }

    if ($ok) { $script:pass++; Write-Host ("  [OK  ] {0}" -f $Name) -ForegroundColor Green }
    else {
        $script:fail++
        Write-Host ("  [FAIL] {0}" -f $Name) -ForegroundColor Red
        if ($Hint) { Write-Host "         $Hint" -ForegroundColor DarkGray }
    }
}

Write-Host ''
Write-Host '=== 배포 전 점검 ===' -ForegroundColor Cyan
Write-Host ''

Write-Host '[클러스터]' -ForegroundColor Cyan
Check 'kubectl 컨텍스트가 hybrid-toy-eks' {
    (kubectl config current-context) -match 'hybrid-toy-eks'
} 'aws eks update-kubeconfig --name hybrid-toy-eks --region ap-northeast-2'

Check '노드 Ready' {
    $n = kubectl get nodes -o json | ConvertFrom-Json
    $n.items.Count -gt 0 -and
    ($n.items | ForEach-Object { ($_.status.conditions | Where-Object type -eq 'Ready').status } ) -notcontains 'False'
}

Check 'app 네임스페이스 존재' { kubectl get ns $NS 2>$null; $LASTEXITCODE -eq 0 } `
    'kubectl apply --server-side -f k8s/namespace/'

Check 'PSA restricted 라벨' {
    (kubectl get ns $NS -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}') -eq 'restricted'
} 'namespace.yaml 로 다시 적용한다. create namespace 로 만들면 라벨이 없다'

Check 'LimitRange 존재' { kubectl -n $NS get limitrange app-limits 2>$null; $LASTEXITCODE -eq 0 }
Check 'ResourceQuota 존재' { kubectl -n $NS get resourcequota app-quota 2>$null; $LASTEXITCODE -eq 0 }

Check 'AWS Load Balancer Controller 동작' {
    $d = kubectl -n kube-system get deploy aws-load-balancer-controller -o json 2>$null | ConvertFrom-Json
    $d.status.readyReplicas -ge 1
} 'LBC 가 없으면 Ingress 를 만들어도 ALB 가 생성되지 않는다'

Write-Host ''
Write-Host '[시크릿]' -ForegroundColor Cyan

Check 'was-secret 존재' { kubectl -n $NS get secret was-secret 2>$null; $LASTEXITCODE -eq 0 } `
    'kubectl -n app create secret generic was-secret --from-literal=DB_USER=app_was --from-literal=DB_PASSWORD=...'

Check 'was-secret 키 2개 (DB_USER / DB_PASSWORD)' {
    $k = (kubectl -n $NS get secret was-secret -o json | ConvertFrom-Json).data.PSObject.Properties.Name
    ($k -contains 'DB_USER') -and ($k -contains 'DB_PASSWORD')
}

Check 'was-secret 의 DB_USER 가 app_was' {
    $v = (kubectl -n $NS get secret was-secret -o jsonpath='{.data.DB_USER}')
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($v)) -eq 'app_was'
} 'admin 계정을 쓰지 않는다 (README §16-7)'

Check 'bff-secret 존재' { kubectl -n $NS get secret bff-secret 2>$null; $LASTEXITCODE -eq 0 }

Check 'JWT_SIGNING_KEY 가 32바이트 이상' {
    $v = (kubectl -n $NS get secret bff-secret -o jsonpath='{.data.JWT_SIGNING_KEY}')
    [Convert]::FromBase64String($v).Length -ge 32
} 'HS256 요건. 미달이면 BFF 가 기동에서 실패한다'

Write-Host ''
Write-Host '[매니페스트 자리표시자]' -ForegroundColor Cyan

$k8s = Join-Path (Split-Path -Parent $PSScriptRoot) 'k8s'

Check 'Ingress ACM ARN 치환됨' {
    $t = Get-Content (Join-Path $k8s 'ingress\patient-web-ingress.yaml') -Raw
    $t -notmatch '__ACM_ARN__'
} 'terraform output -raw acm_certificate_arn 값으로 치환한다. 마크다운 복사 금지'

Check 'cloudflared digest 치환됨' {
    $t = Get-Content (Join-Path $k8s 'cloudflared\deployment.yaml') -Raw
    $t -notmatch '__CLOUDFLARED_DIGEST__'
} 'docker inspect --format=''{{index .RepoDigests 0}}'' cloudflare/cloudflared:latest'

Write-Host ''
Write-Host '[G3 준비]' -ForegroundColor Cyan

Check 'cloudflared-secret 존재' {
    kubectl -n $NS get secret cloudflared-secret 2>$null; $LASTEXITCODE -eq 0
} '리드가 발급한 Tunnel Token 으로 생성한다 (구축설명서 §10.2)'

Check 'TUNNEL_TOKEN 키 존재' {
    $k = (kubectl -n $NS get secret cloudflared-secret -o json 2>$null | ConvertFrom-Json).data.PSObject.Properties.Name
    $k -contains 'TUNNEL_TOKEN'
}

Check 'cloudflared 파드 Ready' {
    $d = kubectl -n $NS get deploy cloudflared -o json 2>$null | ConvertFrom-Json
    $d.status.readyReplicas -ge 1
} 'kubectl apply --server-side -f k8s/cloudflared/'

Write-Host ''
Write-Host '=====================================================' -ForegroundColor Cyan
Write-Host ("  PASS {0}  /  FAIL {1}" -f $pass, $fail)
Write-Host '=====================================================' -ForegroundColor Cyan
Write-Host ''

if ($fail -gt 0) {
    Write-Host 'FAIL 이 남은 채 배포하지 않는다.' -ForegroundColor Red
    Write-Host '파드가 CrashLoopBackOff 로 돌면 원인 구분이 어려워진다.' -ForegroundColor DarkGray
    Write-Host ''
    exit 1
}
Write-Host '배포 가능. .\deploy.ps1 -Service was -Action all' -ForegroundColor Green
Write-Host ''

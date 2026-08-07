# Hybrid Toy Project — 팀 통합 가이드라인

> **이 문서는 프로젝트의 단일 진실 공급원(Single Source of Truth)이다.**
> 모든 팀원은 작업 시작 전 최소 §0 ~ §6 을 읽고, 본인 담당 섹션을 정독한다.
> 문서와 코드가 다르면 **문서가 틀린 것**이다. 발견 즉시 PR로 문서를 고친다.

| 항목 | 값 |
|---|---|
| 문서 버전 | v1.0 |
| 대상 환경 | `dev` (단일 환경) |
| AWS 리전 | `ap-northeast-2` (서울) |
| 프로젝트 식별자 | `hybrid-toy` |
| Terraform 최소 버전 | `>= 1.10.0` |

---

## 목차

- [§0. 프로젝트 개요](#0-프로젝트-개요)
- [§1. 서비스 리스트](#1-서비스-리스트)
- [§2. 네트워크 설계](#2-네트워크-설계)
- [§3. 리포지토리 구조 및 소유권](#3-리포지토리-구조-및-소유권)
- [§4. 협업 규칙](#4-협업-규칙)
- [§5. 기술 스택 및 버전 고정](#5-기술-스택-및-버전-고정)
- [§6. 표준 및 명명 규칙](#6-표준-및-명명-규칙)
- [§7. 설계상 핵심 판단](#7-설계상-핵심-판단)
- [§8. apply 전 필수 선조치](#8-apply-전-필수-선조치-블로커)
- [§9. 전체 실행 순서 및 게이트](#9-전체-실행-순서-및-게이트)
- [§10. 인프라 리드팀 실행 절차](#10-인프라-리드팀-실행-절차)
- [§11. EKS팀 실행 절차](#11-eks팀-실행-절차)
- [§12. DB팀 실행 절차](#12-db팀-실행-절차)
- [§13. 보안 및 암호화 기준](#13-보안-및-암호화-기준)
- [§14. 완료 기준(DoD) 체크리스트](#14-완료-기준dod-체크리스트)
- [§15. 트러블슈팅](#15-트러블슈팅)
- [§16. 금지 사항](#16-금지-사항)
- [§17. 미결정 사항 및 백로그](#17-미결정-사항-및-백로그)
- [§18. 온프레미스(OKD)팀 가이드](#18-온프레미스okd팀-가이드)

---

## §0. 프로젝트 개요

### 0.1 목표

온프레미스(OKD)와 AWS 클라우드를 Cloudflare로 연결하는 하이브리드 구조의 **최소 동작 뼈대**를 구축한다.

### 0.2 반드시 구성해야 하는 2개 흐름

**흐름 1 — 외부 사용자 (환자)**

```
일반사용자 → Browser
  → Cloudflare (WAF / Rate Limit / DDoS)
  → ALB (ACM TLS 종단)
  → EKS: patient-web → bff → was
  → 공통 RDS
```

**흐름 2 — 내부 사용자 (직원)**

```
내부사용자 → OKD Web Pod (사내망)
  → Cloudflare Access (Service Token 인증)
  → Cloudflare Tunnel
  → EKS: cloudflared Pod → bff → was
  → 공통 RDS
```

### 0.3 스코프 원칙

> **이 2개 흐름 "만" 먼저 완성한다. 그 외 일체의 디테일은 완성 후 추가한다.**

기능 추가 제안은 §17 백로그에 기록만 하고 착수하지 않는다. 뼈대 완성 전 살을 붙이면 통합 지점이 흔들려 전체가 지연된다.

### 0.4 전제 조건

| # | 조건 |
|---|---|
| 1 | 온프레미스 OKD 환경은 **이미 구성 완료** 상태 |
| 2 | Cloudflare 설정은 **대시보드 수동 작업** (cloudflared Pod 제외). Terraform 관리 대상 아님 |
| 3 | Git repo 1개를 전원이 공유. `terraform apply`는 **최고관리자 1인 전담** |
| 4 | 팀별 state 분리 없음 — 시간 제약. 단일 state 운영 |
| 5 | S3 버킷은 **필수 옵션만** 사용 |

---

## §1. 서비스 리스트

### 1.1 애플리케이션 서비스 (EKS 배포 대상)

| 서비스 | ECR 리포지토리 | K8s Service 명 | 클러스터 내 DNS | 포트 | 담당 |
|---|---|---|---|---|---|
| `patient-web` | `hybrid-toy/patient-web` | `patient-web-svc` | `patient-web-svc.app.svc.cluster.local` | 8080 | EKS팀 — Web |
| `bff` | `hybrid-toy/bff` | `bff-svc` | `bff-svc.app.svc.cluster.local` | 8080 | EKS팀 — BFF |
| `was` | `hybrid-toy/was` | `was-svc` | `was-svc.app.svc.cluster.local` | 8080 | EKS팀 — WAS |
| `cloudflared` | (공식 이미지 사용) | 없음 (아웃바운드 전용) | — | — | EKS팀 — BFF |

- 네임스페이스: **`app`** (cloudflared 포함 전부 동일)
- Service 타입: 전부 **ClusterIP**. `patient-web`만 Ingress를 통해 외부 노출
- `cloudflared`는 Cloudflare 엣지로 **아웃바운드 연결만** 하므로 Service·Ingress 불필요

### 1.2 서비스 간 호출 관계

```
[외부] ALB ──────────────→ patient-web-svc:8080 ──┐
                                                    ├──→ bff-svc:8080 ──→ was-svc:8080 ──→ RDS:3306
[내부] cloudflared Pod ────────────────────────────┘
```

- `bff`는 **외부·내부 두 흐름의 공통 수렴점**이다. 두 경로 모두 여기서 합류한다.
- `was`만 RDS에 접근한다. `bff`·`patient-web`은 DB 자격증명을 갖지 않는다.

### 1.3 AWS 인프라 리소스

| 리소스 | 이름 / 식별자 | Terraform 관리 | 담당 |
|---|---|---|---|
| VPC | `hybrid-toy-vpc` | ✅ `modules/network` | 인프라 리드 |
| Subnet (Public ×2) | ALB 배치용 | ✅ `modules/network` | 인프라 리드 |
| Subnet (Private ×2) | EKS 워커 배치용 | ✅ `modules/network` | 인프라 리드 |
| Subnet (Database ×2) | RDS 전용 | ✅ `modules/network` | 인프라 리드 |
| NAT Gateway ×1 | 단일 NAT (비용 절감) | ✅ `modules/network` | 인프라 리드 |
| EKS Cluster | `hybrid-toy-eks` | ✅ `modules/eks` | 인프라 리드 |
| EKS Managed Node Group | `default` (t3.medium ×2) | ✅ `modules/eks` | 인프라 리드 |
| IRSA Role | `hybrid-toy-eks-lbc-irsa` | ✅ `modules/eks` | 인프라 리드 |
| ECR ×3 | §1.1 참조 | ✅ `modules/ecr` | 인프라 리드 생성 / EKS팀 사용 |
| RDS (MySQL 8.0) | `hybrid-toy-rds` | ✅ `modules/rds` | 인프라 리드 생성 / DB팀 운영 |
| RDS Security Group | `hybrid-toy-rds-*` | ✅ `modules/rds` | 인프라 리드 |
| ACM 인증서 | `var.alb_domain_name` | ✅ `envs/dev/main.tf` | 인프라 리드 |
| S3 (tfstate) | 부트스트랩 생성 | ✅ `backend-bootstrap` | 인프라 리드 |
| **ALB** | Ingress가 동적 생성 | ❌ **K8s Ingress로 생성** | EKS팀 — Web |

> ⚠️ **ALB는 Terraform이 만들지 않는다.** AWS Load Balancer Controller가 Ingress 리소스를 감지해 동적 생성한다. Terraform은 IRSA 권한과 ACM 인증서까지만 준비한다. §7.1 참조.

### 1.4 클러스터 애드온

| 애드온 | 설치 주체 | 설치 방식 | 목적 |
|---|---|---|---|
| CoreDNS | Terraform | EKS Addon | 클러스터 내부 DNS |
| kube-proxy | Terraform | EKS Addon | Service 네트워킹 |
| VPC CNI | Terraform | EKS Addon | 파드 IP 할당 |
| EKS Pod Identity Agent | Terraform | EKS Addon | 파드 IAM 인증 |
| AWS Load Balancer Controller | **인프라 리드** | **Helm (수동)** | Ingress → ALB 변환 |

### 1.5 Cloudflare 리소스 (전부 대시보드 수동)

| 리소스 | 용도 | 흐름 | 담당 |
|---|---|---|---|
| DNS Zone | 도메인 관리 | 공통 | 인프라 리드 |
| DNS Record (ACM 검증용 CNAME) | 인증서 발급 검증 | 1 | 인프라 리드 |
| DNS Record (앱 도메인 → ALB) | 프록시 경유 | 1 | 인프라 리드 |
| WAF Rule / Rate Limit / DDoS | 외부 트래픽 필터 | 1 | 인프라 리드 |
| SSL/TLS 모드 = Full (strict) | 종단간 TLS | 1 | 인프라 리드 |
| Zero Trust — Tunnel | 내부망 → EKS 연결 | 2 | 인프라 리드 |
| Zero Trust — Access Application | 내부 엔드포인트 보호 | 2 | 인프라 리드 |
| Zero Trust — Service Token | OKD 인증 수단 | 2 | 인프라 리드 → OKD팀 |

---

## §2. 네트워크 설계

### 2.1 서브넷 구성 — 총 6개 (3-tier × 2 AZ)

VPC CIDR `10.0.0.0/16`, AZ: `ap-northeast-2a`, `ap-northeast-2c`

| Tier | CIDR | 배치 대상 | 인터넷 경로 | 개수 |
|---|---|---|---|---|
| **Public** | `10.0.0.0/24`, `10.0.1.0/24` | ALB | IGW (인바운드/아웃바운드) | 2 |
| **Private** | `10.0.10.0/24`, `10.0.11.0/24` | EKS 워커 노드, 전체 파드, cloudflared | NAT (아웃바운드 전용) | 2 |
| **Database** | `10.0.20.0/24`, `10.0.21.0/24` | RDS | **없음 (완전 격리)** | 2 |

### 2.2 서브넷 태그 정책

| Tier | 태그 | 이유 |
|---|---|---|
| Public | `kubernetes.io/role/elb = 1`<br>`kubernetes.io/cluster/hybrid-toy-eks = shared` | LB Controller가 외부 ALB 배치 후보로 인식 |
| Private | `kubernetes.io/role/internal-elb = 1`<br>`kubernetes.io/cluster/hybrid-toy-eks = shared` | 내부 NLB/ALB 배치 후보 |
| Database | `Tier = database` **만** | ⚠️ `kubernetes.io/*` 태그를 넣으면 LB Controller가 DB 계층에 ELB ENI를 꽂을 수 있다. 격리 설계가 무의미해진다 |

### 2.3 RDS 접근 통제 — 이중 방어

| 계층 | 통제 수단 | 현재 상태 |
|---|---|---|
| 네트워크 | DB 전용 서브넷 분리 + NAT 라우트 없음 | ✅ 적용 |
| 방화벽 | Security Group — EKS 노드 SG 출처의 3306만 허용 | ✅ 적용 |
| 접근성 | `publicly_accessible = false` | ✅ 적용 |

**결과: 로컬 PC에서 RDS 직접 접속 불가.** DB팀은 §12.1의 우회 경로를 사용한다.

### 2.4 서브넷 분리 근거

| 근거 | 설명 |
|---|---|
| Defense in depth | SG 규칙 하나 잘못 수정해도 서브넷 경계가 2차 방어선으로 남는다 |
| IP 고갈 방지 | VPC CNI는 파드마다 ENI 보조 IP를 소비한다. 워커가 `/24`를 잠식하면 RDS 확장(Read Replica, Multi-AZ) 시 IP 부족으로 막힌다 |
| 감사 대응 | `patient-web` — 의료 도메인. 데이터 계층 네트워크 분리는 사실상 필수 요건 |

> ⏱️ **타이밍 주의:** apply 후 서브넷 그룹을 바꾸면 `aws_db_subnet_group` 교체 → **RDS 인스턴스 재생성**이 트리거된다. 데이터가 들어간 뒤에는 마이그레이션 작업이 된다. 이 구조는 **apply 전에 확정**되었다.

### 2.5 DB 서브넷에 NAT 라우트를 붙이지 않은 이유

RDS는 아웃바운드 인터넷이 불필요하다. 향후 S3 export나 Lambda 연동이 필요해지면 **NAT가 아니라 VPC Endpoint**를 추가하는 것이 정답이다.

---

## §3. 리포지토리 구조 및 소유권

```
infra/
├── README.md                      # 이 문서 — 전원 필독
├── .gitignore
├── backend-bootstrap/             # [인프라 리드] 최초 1회만. S3 state 버킷
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── envs/dev/                      # [인프라 리드] 유일한 apply 지점
│   ├── backend.tf                 # S3 backend + native locking
│   ├── providers.tf
│   ├── main.tf                    # 모든 모듈 조립
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example   # 실 tfvars는 커밋 금지
└── modules/
    ├── network/                   # [인프라 리드] VPC, 3-tier Subnet, NAT
    ├── eks/                       # [인프라 리드] EKS, NodeGroup, IRSA
    ├── ecr/                       # [EKS팀]      리포지토리 정의
    └── rds/                       # [DB팀]       RDS, SG, SubnetGroup
```

### 3.1 디렉토리별 편집 권한

| 경로 | 편집 가능 | 비고 |
|---|---|---|
| `backend-bootstrap/` | 인프라 리드 | **apply는 최초 1회. 재실행 절대 금지** |
| `envs/dev/` | 인프라 리드 | 모듈 조립 및 apply 지점 |
| `modules/network/` | 인프라 리드 | |
| `modules/eks/` | 인프라 리드 | |
| `modules/ecr/` | EKS팀 | PR 필요 |
| `modules/rds/` | DB팀 | PR 필요 |
| `k8s/` (별도 생성) | EKS팀 | 매니페스트. Terraform 관리 대상 아님 |

### 3.2 K8s 매니페스트 디렉토리 (EKS팀이 생성)

```
k8s/
├── namespace.yaml
├── patient-web/{deployment,service}.yaml
├── bff/{deployment,service}.yaml
├── was/{deployment,service,secret.example}.yaml
├── cloudflared/deployment.yaml
└── ingress/patient-web-ingress.yaml
```

---

## §4. 협업 규칙

### 4.1 Terraform 운영 규칙

| 규칙 | 내용 |
|---|---|
| **apply 권한** | **인프라 리드 1인 전담.** 다른 팀원은 `terraform apply` 실행 금지 |
| **plan 권한** | 전원 가능. 본인 모듈 변경 검증용 |
| **state** | 단일 state (`envs/dev/terraform.tfstate`). 팀별 분리 없음 |
| **Lock** | S3 Native Locking (`use_lockfile = true`). DynamoDB 미사용 |
| **작업 흐름** | 모듈 수정 → PR → 리드 리뷰 → merge → 리드가 apply |
| **커밋 금지** | `*.tfstate`, `*.tfvars`, `.terraform/`, `*.pem`, `*.key` |

### 4.2 apply 전 필수 절차

```bash
terraform fmt -recursive     # 포맷 통일
terraform validate           # 문법 검증
terraform plan -out=tfplan   # 변경 리소스 수 육안 확인
terraform apply tfplan       # 저장된 plan으로만 apply
```

> `terraform apply` 단독 실행 금지. plan 파일을 거쳐야 검토한 내용과 실제 적용이 일치한다.

### 4.3 Git 규칙

| 항목 | 규칙 |
|---|---|
| 브랜치 | `feature/<team>-<내용>` (예: `feature/eks-bff-deployment`) |
| 커밋 | `[team] 내용` (예: `[db] commondb DDL 초안`) |
| PR | 본인 담당 디렉토리 외 파일 변경 시 해당 팀 리뷰 필수 |
| `envs/dev/main.tf` | 인프라 리드만 수정. 다른 팀은 요청만 |

---

## §5. 기술 스택 및 버전 고정

2026년 8월 기준 팩트체크 결과. **임의 변경 금지.**

| 항목 | 고정 버전 | 검증 근거 |
|---|---|---|
| Terraform | `>= 1.10.0` | S3 native locking(`use_lockfile`) 지원 최소 버전 |
| AWS Provider | `~> 6.0` | v5는 EOL 임박. 리전 관리 개선된 v6 채택 |
| `terraform-aws-modules/eks/aws` | `~> 21.0` | 최신 21.24.1. v20 대비 Cluster Access Management(access_entries) 전환 완료 |
| `terraform-aws-modules/vpc/aws` | `~> 5.0` | `database_subnets` 1급 인자 지원 |
| `terraform-aws-modules/iam` | `~> 5.0` | IRSA 서브모듈 |
| Kubernetes | `1.33` | EKS 지원 버전 |
| MySQL | `8.0` | RDS 엔진 |
| 노드 인스턴스 | `t3.medium` × 2 (min 1 / max 3) | 토이 프로젝트 규모 |
| RDS 인스턴스 | `db.t3.micro`, 20GB | 토이 프로젝트 규모 |

### 5.1 DynamoDB Lock Table을 쓰지 않는 이유

Terraform 1.10부터 S3 backend가 **자체 native locking**을 지원한다. 별도 DynamoDB 테이블은 legacy 취급이며, "S3 필수 옵션만 사용" 조건에 정확히 부합한다. 또한 apply 주체가 1인이라 동시 실행 경쟁 자체가 거의 없다.

### 5.2 S3 state 버킷 옵션 — 3개만

| 옵션 | 목적 |
|---|---|
| Versioning | state 손상 시 롤백 |
| SSE-S3 (AES256) | 저장 암호화 |
| Public Access Block (4종 전부) | 퍼블릭 노출 차단 |

Object Lock, Replication, Lifecycle 등은 오버스펙 — 적용하지 않는다.

---

## §6. 표준 및 명명 규칙

### 6.1 컨테이너 표준 (EKS팀 전원 준수)

| 항목 | 표준 |
|---|---|
| 컨테이너 포트 | **8080** (3개 서비스 전부 동일) |
| K8s Service 포트 | **8080** → targetPort 8080 |
| Liveness 엔드포인트 | `GET /healthz` → 200 |
| Readiness 엔드포인트 | `GET /readyz` → 200 |
| 이미지 태그 | **git short SHA** (`git rev-parse --short HEAD`) |
| 베이스 이미지 | 각 서비스 자율. 단 `latest` 태그 금지 |

> ⚠️ **`/healthz` 미구현 시 ALB Target Group이 영구히 unhealthy 상태로 남는다.** 원인 파악에 반나절이 날아가는 대표적 사고다. §15 참조.

### 6.2 환경변수 계약 (서비스 간 인터페이스)

| 서비스 | 환경변수 | 값 | 주입 방식 |
|---|---|---|---|
| `patient-web` | `BFF_BASE_URL` | `http://bff-svc.app.svc.cluster.local:8080` | ConfigMap |
| `bff` | `WAS_BASE_URL` | `http://was-svc.app.svc.cluster.local:8080` | ConfigMap |
| `was` | `DB_HOST` | RDS 엔드포인트 | ConfigMap |
| `was` | `DB_PORT` | `3306` | ConfigMap |
| `was` | `DB_NAME` | `commondb` | ConfigMap |
| `was` | `DB_USER` | `app_was` | **Secret** |
| `was` | `DB_PASSWORD` | (DB팀 발급) | **Secret** |
| `cloudflared` | `TUNNEL_TOKEN` | (인프라 리드 발급) | **Secret** |

> **하드코딩 금지.** URL을 코드에 박으면 네임스페이스 변경 시 전 서비스를 재빌드해야 한다.

### 6.3 리소스 명명 규칙

| 대상 | 규칙 | 예시 |
|---|---|---|
| AWS 리소스 | `hybrid-toy-<리소스>` | `hybrid-toy-eks` |
| ECR 리포지토리 | `hybrid-toy/<서비스>` | `hybrid-toy/bff` |
| K8s Service | `<서비스>-svc` | `bff-svc` |
| K8s Deployment | `<서비스>` | `bff` |
| K8s Secret | `<서비스>-secret` | `was-secret` |

### 6.4 공통 태그

전 AWS 리소스에 자동 부착:

```hcl
Project     = "hybrid-toy"
Environment = "dev"
ManagedBy   = "terraform"
```

---

## §7. 설계상 핵심 판단

각 결정의 **이유**를 명시한다. 이유를 모르면 나중에 잘못 되돌린다.

### 7.1 ALB를 Terraform으로 만들지 않는다

AWS Load Balancer Controller가 Ingress를 감지해 ALB를 동적 생성하는 것이 EKS 표준 패턴이다. Terraform으로 ALB를 별도 생성하면 Target Group 등록을 수동 관리해야 하고, 파드 IP 변경마다 드리프트가 발생한다.

**Terraform 담당 범위:** IRSA 권한 + ACM 인증서
**EKS팀 담당 범위:** Ingress 리소스 작성 → ALB 실제 생성

### 7.2 ECR을 `-target`으로 선행 apply 한다

ECR은 의존성이 전혀 없다. 먼저 생성하면 EKS팀이 클러스터 생성 25분을 기다리지 않고 즉시 이미지 빌드·푸시를 시작할 수 있다.

`-target`은 평시엔 안티패턴이지만 **팀 언블로킹 용도는 정당하다.** 단, 직후 반드시 전체 apply로 state를 정합화한다.

### 7.3 `create_database_subnet_group = false`

VPC 모듈도 DB 서브넷 그룹을 만들 수 있지만, `modules/rds`에 이미 `aws_db_subnet_group`이 있다. 둘 다 켜면 중복 리소스가 생겨 추적이 어려워진다. **DB 관련 리소스는 DB팀 디렉토리에 모은다** — 협업 경계 명확화.

### 7.4 `single_nat_gateway = true`

NAT Gateway는 시간당 과금 + 데이터 처리 과금이다. AZ당 1개면 비용이 2배다. 토이 프로젝트는 단일 NAT로 충분하다.

**대가:** AZ 장애 시 해당 NAT를 쓰는 전체 파드의 아웃바운드가 끊긴다(SPOF). 운영 전환 시 반드시 AZ당 NAT로 변경.

### 7.5 `image_tag_mutability = "IMMUTABLE"`

동일 태그 재푸시를 차단한다. `:latest`를 덮어쓰면 롤백 시 어떤 이미지였는지 추적 불가능해진다.

**대가:** `:latest` 푸시가 실패한다. git SHA 태그를 강제한다(§6.1).

### 7.6 EKS 엔드포인트 public + private 병행

토이 프로젝트라 팀원들이 각자 PC에서 `kubectl`을 써야 한다. private 전용으로 하면 Bastion이나 VPN이 필요해 셋업 비용이 커진다.

**대가:** API 서버가 인터넷에 노출된다. IAM 인증이 걸려 있어 즉각적 위험은 아니나, 운영 전환 시 private 전용 + CIDR 제한이 필수.

### 7.7 `skip_final_snapshot = true`

`terraform destroy` 시 최종 스냅샷을 만들지 않는다. 토이 프로젝트에서 destroy가 스냅샷 생성 대기로 막히는 것을 방지한다.

**대가:** destroy하면 데이터가 완전히 사라진다. **DB팀은 스키마 DDL을 반드시 git에 커밋해 둔다.**

### 7.8 cloudflared를 BFF 담당이 맡는다

cloudflared는 `bff-svc`를 직접 호출한다. 호출 대상을 아는 사람이 배포하는 것이 경계상 자연스럽다. Web 담당이 맡으면 BFF 스펙 변경 시 매번 소통 비용이 발생한다.

---

## §8. apply 전 필수 선조치 (블로커)

> 🚨 **아래 3가지를 처리하지 않고 apply하면, 완료 후에도 EKS팀·DB팀이 아무 작업도 못 한다.**

### 8.1 EKS 접근 권한 부여 — 최우선

`enable_cluster_creator_admin_permissions = true`는 **apply를 실행한 IAM principal(리드) 1명만** 관리자로 등록한다. 나머지 팀원은 `kubectl` 자체가 동작하지 않는다.

`modules/eks/main.tf` 에 추가:

```hcl
access_entries = {
  for name, arn in var.developer_iam_arns : name => {
    principal_arn = arn
    policy_associations = {
      admin = {
        policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        access_scope = { type = "cluster" }
      }
    }
  }
}
```

`modules/eks/variables.tf` 에 추가:

```hcl
variable "developer_iam_arns" {
  description = "클러스터 접근이 필요한 팀원 IAM ARN"
  type        = map(string)
  default     = {}
}
```

`envs/dev/main.tf` 의 `module "eks"` 블록에 추가:

```hcl
developer_iam_arns = {
  web = "arn:aws:iam::<ACCOUNT_ID>:user/web-dev"
  bff = "arn:aws:iam::<ACCOUNT_ID>:user/bff-dev"
  was = "arn:aws:iam::<ACCOUNT_ID>:user/was-dev"
  db  = "arn:aws:iam::<ACCOUNT_ID>:user/db-dev"
}
```

> 토이 프로젝트라 전원 ClusterAdmin으로 간다. 실무에서는 네임스페이스 스코프로 좁혀야 한다.

### 8.2 S3 버킷명 확정

`backend-bootstrap/variables.tf` 와 `envs/dev/backend.tf` 의 `CHANGE-ME-tfstate-hybrid-toy` 를 **동일한 실제 값**으로 교체한다.

- S3 버킷명은 **전역 유일**해야 한다 (전 세계 모든 AWS 계정 통틀어)
- 두 파일의 값이 다르면 `terraform init` 단계에서 즉시 실패한다
- 권장 형식: `hybrid-toy-tfstate-<계정ID 뒤 6자리>`

### 8.3 ECR 태그 정책 사전 공지

`IMMUTABLE` 설정으로 `:latest` 재푸시가 실패한다. **EKS팀 전원에게 git SHA 태그 강제를 공지**한다.

이의가 있으면 **apply 전에** `MUTABLE`로 변경해야 한다. 생성 후 변경하려면 리포지토리 재생성이 필요하다.

### 8.4 (권장) DB 보안 강화 — §13 참조

TLS 강제와 Secrets Manager 전환은 **apply 전에 결정**하는 것이 비용 0이다. 결정 사항을 §13.5 표에 기록한 뒤 진행한다.

---

## §9. 전체 실행 순서 및 게이트

### 9.1 페이즈 구조

| 페이즈 | 내용 | 예상 소요 | 게이트 |
|---|---|---|---|
| **P0** | AWS 불필요 작업 — 3팀 완전 병렬 | ~반나절 | — |
| **P1** | 인프라 리드 단독 apply | ~40분 | **G1**: 클러스터·ECR·RDS 생성 완료 |
| **P2** | 3팀 병렬 개발 | 1~2일 | **G2**: 흐름1(외부) 소통 확인 |
| **P3** | 흐름2(내부 터널) 연결 | ~반나절 | **G3**: 전체 완료 |

### 9.2 의존 관계도

```
                    ┌─→ ECR (선행 apply, ~1분)
인프라 apply ──G1──┼─→ WAS ──→ BFF ──→ Web ──→ Ingress ──G2──→ 흐름1 완료
                    │                    └──→ cloudflared ──G3──→ 흐름2 완료
                    └─→ DB 스키마 ──┘
```

### 9.3 임계 경로

**`WAS → BFF → Web`이 임계 경로다.** WAS가 하루 밀리면 전체가 하루 밀린다.

DB 스키마는 WAS의 커넥션 확인만 되면 병렬로 따라붙을 수 있어 임계 경로가 아니다. **WAS 담당은 스키마 대기로 멈추지 말 것.**

### 9.4 게이트 통과 조건

| 게이트 | 통과 조건 |
|---|---|
| **G1** | `terraform output` 전체 값 공유 완료 + 전 팀원 `kubectl get nodes` 성공 |
| **G2** | 브라우저에서 앱 도메인 접속 → patient-web 화면 표시 → BFF 경유 WAS 응답 확인 |
| **G3** | OKD Web Pod에서 Access 엔드포인트 호출 → BFF 응답 수신 |

---

## §10. 인프라 리드팀 실행 절차

### P0 — 사전 준비

| # | 작업 | 산출물 |
|---|---|---|
| 1 | §8의 선조치 3가지 완료 | 수정된 `.tf` |
| 2 | 팀원 IAM User 생성 + AccessKey 안전 배포 | 4명분 자격증명 |
| 3 | Cloudflare에 도메인 등록, 네임서버 이전 완료 (**Active** 상태 확인) | 활성 Zone |
| 4 | `terraform fmt -recursive && terraform validate` | 문법 검증 통과 |
| 5 | 팀원에게 이 README 공유 + §6 표준 합의 | — |

> ⏳ Cloudflare 네임서버 이전은 전파에 최대 24시간이 걸린다. **가장 먼저 시작할 것.**

### P1-1 — state 버킷 생성 (최초 1회, 영구히 재실행 금지)

```bash
cd backend-bootstrap
terraform init
terraform apply
# output의 state_bucket_name 값을 envs/dev/backend.tf 에 반영
```

### P1-2 — ECR 선행 apply (팀 언블로킹)

```bash
cd ../envs/dev
cp terraform.tfvars.example terraform.tfvars   # 값 채우기 (커밋 금지)
terraform init
terraform apply -target=module.ecr             # ~1분
terraform output ecr_repository_urls           # 즉시 EKS팀에 공유
```

### P1-3 — 전체 생성

```bash
terraform plan -out=tfplan     # 리소스 수 육안 확인
terraform apply tfplan         # EKS ~15분 + RDS ~10분
terraform output               # 전 팀에 공유
```

### P1-4 — ACM 인증서 검증

```bash
aws acm describe-certificate \
  --certificate-arn $(terraform output -raw acm_certificate_arn) \
  --query 'Certificate.DomainValidationOptions'
```

Cloudflare 대시보드 → DNS → 위에서 나온 CNAME 추가.

> 🚨 **검증용 CNAME은 반드시 "DNS only"(회색 구름)으로 설정한다.**
> 주황 구름(프록시)으로 두면 Cloudflare가 응답을 가로채 ACM 검증이 **영원히 Pending**에 머문다. 가장 흔한 삽질 포인트다.

### P1-5 — kubeconfig 및 LB Controller 설치

```bash
aws eks update-kubeconfig --region ap-northeast-2 --name hybrid-toy-eks
kubectl get nodes    # Ready 2개 확인

# 네임스페이스 생성
kubectl create namespace app

# AWS Load Balancer Controller — Ingress 생성의 전제조건
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=hybrid-toy-eks \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<lbc_irsa_role_arn>

kubectl -n kube-system rollout status deploy/aws-load-balancer-controller
```

### 🚩 G1 선언 — 전 팀 공유 항목

```
EKS 클러스터명       : hybrid-toy-eks
kubeconfig 명령      : aws eks update-kubeconfig --region ap-northeast-2 --name hybrid-toy-eks
ECR URL (3개)        : terraform output ecr_repository_urls
RDS 엔드포인트/포트   : terraform output rds_endpoint / 3306
ACM 인증서 ARN       : terraform output acm_certificate_arn
네임스페이스          : app
```

### P2 — 지원 및 Cloudflare 구성

| # | 작업 | 비고 |
|---|---|---|
| 1 | EKS팀 Ingress 이슈 대응 | Target Group unhealthy 등 |
| 2 | Cloudflare **SSL/TLS 모드 = Full (strict)** 설정 | Flexible로 두면 무한 리다이렉트 루프 |
| 3 | Web 담당에게 ALB DNS명 수령 → Cloudflare DNS에 CNAME 등록 (**주황 구름 ON**) | 흐름1 완성 |
| 4 | WAF Managed Ruleset 활성화 | |
| 5 | Rate Limiting Rule 구성 | |
| 6 | Bot Fight Mode 활성화 | |

### P3 — 내부 흐름 구성

| # | 작업 | 산출물 → 전달 대상 |
|---|---|---|
| 1 | Zero Trust → Networks → Tunnels → **Tunnel 생성** | Tunnel Token → BFF 담당 |
| 2 | Tunnel의 Public Hostname 설정: 내부 도메인 → `http://bff-svc.app.svc.cluster.local:8080` | — |
| 3 | Zero Trust → Access → **Application 생성** (도메인: 위 내부 도메인) | — |
| 4 | Access Policy 추가 — **Action을 `Service Auth`로 지정** | — |
| 5 | **Service Token 발급** | Client ID + Secret → OKD팀 |

> 🚨 **Access Policy의 Action은 반드시 `Service Auth`여야 한다.**
> `Allow`로 두면 Service Token을 보내도 여전히 사용자 로그인(IdP)을 요구해 OKD Pod가 인증 페이지 HTML을 받는다.

---

## §11. EKS팀 실행 절차

### 11.0 3인 공통 규칙

| 항목 | 규칙 |
|---|---|
| 네임스페이스 | 전부 `app` |
| 컨테이너 포트 | 8080 |
| 헬스체크 | `/healthz`, `/readyz` |
| 이미지 태그 | git short SHA (`:latest` 금지) |
| 하위 서비스 주소 | ConfigMap 주입. 하드코딩 금지 |
| 매니페스트 | `k8s/<서비스>/` 에 커밋 |

### 11.1 공통 P0 — 클러스터 없이 가능

| # | 작업 |
|---|---|
| 1 | Dockerfile 작성 + 로컬 빌드 성공 |
| 2 | **`/healthz`, `/readyz` 엔드포인트 구현** (200 응답) |
| 3 | `docker-compose`로 web→bff→was→mysql 로컬 통합 확인 |
| 4 | `k8s/` 매니페스트 뼈대 작성 (Deployment / Service) |
| 5 | 환경변수를 §6.2 계약대로 읽도록 구현 |

### 11.2 공통 P1 — ECR 준비되면 즉시 (클러스터 대기 불필요)

```bash
ACCOUNT=<ACCOUNT_ID>
REGION=ap-northeast-2
REGISTRY=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com

aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin $REGISTRY

TAG=$(git rev-parse --short HEAD)     # ⚠️ :latest 금지 (IMMUTABLE)
docker build -t $REGISTRY/hybrid-toy/<서비스>:$TAG .
docker push $REGISTRY/hybrid-toy/<서비스>:$TAG
```

> Apple Silicon(M1/M2/M3) 사용자는 **`--platform linux/amd64`를 반드시 지정**한다. 미지정 시 ARM 이미지가 푸시되어 파드가 `exec format error`로 크래시한다.
> ```bash
> docker build --platform linux/amd64 -t ... .
> ```

### 11.3 담당별 P2 — 의존 역순으로 배포

> **배포 순서는 `WAS → BFF → Web`이다.** 하위 서비스가 없으면 상위가 헬스체크에 실패해 무한 재시작한다.

#### ① WAS 담당 — 최우선 (나머지 2명이 대기 중)

| 순서 | 작업 | 검증 방법 |
|---|---|---|
| 1 | RDS 접속정보 Secret 생성 | `kubectl -n app get secret was-secret` |
| 2 | Deployment + Service(ClusterIP 8080) 배포 | `kubectl -n app get pod` → Running |
| 3 | DB 커넥션 풀 기동 확인 | 파드 로그에 connection established |
| 4 | 헬스체크 응답 확인 | 아래 명령 |

```bash
kubectl -n app run tmp --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s http://was-svc.app.svc.cluster.local:8080/healthz
```

> **DB팀 스키마가 아직 없어도 진행한다.** 커넥션 수립만 확인하고 다음 단계로 넘어갈 것. 스키마 대기로 멈추면 BFF·Web이 전부 밀린다.

Secret 생성 예시:

```bash
kubectl -n app create secret generic was-secret \
  --from-literal=DB_USER=app_was \
  --from-literal=DB_PASSWORD='<DB팀 발급 비밀번호>'
```

#### ② BFF 담당 — WAS Service 생성 후

| 순서 | 작업 | 검증 방법 |
|---|---|---|
| 1 | ConfigMap에 `WAS_BASE_URL` 주입 | — |
| 2 | Deployment + Service(ClusterIP 8080) 배포 | `kubectl -n app get pod` |
| 3 | BFF → WAS 프록시 호출 검증 | 임시 파드에서 curl |
| 4 | **[P3]** cloudflared Deployment 배포 | 아래 참조 |

```bash
kubectl -n app run tmp --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s http://bff-svc.app.svc.cluster.local:8080/healthz
```

**P3 — cloudflared 배포** (인프라 리드에게 Tunnel Token 수령 후)

```bash
kubectl -n app create secret generic cloudflared-secret \
  --from-literal=TUNNEL_TOKEN='<인프라 리드 발급 토큰>'
```

```yaml
# k8s/cloudflared/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: app
spec:
  replicas: 2                    # 터널 이중화. 1개면 파드 재시작 중 내부 흐름 단절
  selector:
    matchLabels: { app: cloudflared }
  template:
    metadata:
      labels: { app: cloudflared }
    spec:
      containers:
        - name: cloudflared
          image: cloudflare/cloudflared:latest
          args: ["tunnel", "--no-autoupdate", "run"]
          env:
            - name: TUNNEL_TOKEN
              valueFrom:
                secretKeyRef:
                  name: cloudflared-secret
                  key: TUNNEL_TOKEN
```

> cloudflared는 **아웃바운드 연결만** 한다. Service·Ingress·인바운드 SG 규칙 전부 불필요하다.
> 검증: `kubectl -n app logs deploy/cloudflared` → 등록 성공 로그 + Cloudflare 대시보드에서 Tunnel 상태 **HEALTHY**

#### ③ Web 담당 — BFF Service 생성 후

| 순서 | 작업 | 검증 방법 |
|---|---|---|
| 1 | ConfigMap에 `BFF_BASE_URL` 주입 | — |
| 2 | Deployment + Service 배포 | `kubectl -n app get pod` |
| 3 | Web → BFF 호출 검증 | 임시 파드에서 curl |
| 4 | **Ingress 작성 — ALB 실제 생성 지점** | 아래 참조 |
| 5 | ALB DNS명 확보 → 인프라 리드에게 전달 | `kubectl -n app get ingress` |

```yaml
# k8s/ingress/patient-web-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: patient-web
  namespace: app
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: <ACM_ARN>
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: patient-web-svc
                port:
                  number: 8080
```

```bash
kubectl -n app get ingress patient-web -w   # ADDRESS 필드에 ALB DNS명이 뜰 때까지 (~3분)
```

이후 인프라 리드가 Cloudflare DNS에 CNAME 등록(주황 구름 ON) → **🚩 G2: 흐름1 완성**

---

## §12. DB팀 실행 절차

### 12.1 ⚠️ 선결 문제 — 접속 경로

RDS는 DB 전용 서브넷 + SG(EKS 노드 SG만 허용) 안에 있다. **로컬 PC에서 직접 접속이 불가능하다.**

| 방식 | 평가 |
|---|---|
| **클러스터 내 임시 파드** | ✅ **권장.** 추가 인프라 0, 보안 설계 유지 |
| Bastion EC2 | 리소스·SG 추가 필요. 오버킬 |
| SG에 내 IP 임시 허용 | ❌ **금지.** 격리 설계를 무의미하게 만든다 |

```bash
kubectl -n app run mysql-cli --rm -it --image=mysql:8.0 --restart=Never -- \
  mysql -h <RDS_ENDPOINT> -u admin -p
```

파드 트래픽이 EKS 노드 SG를 경유하므로 RDS SG를 통과한다.

### 12.2 실행 순서

| 페이즈 | 작업 | 비고 |
|---|---|---|
| **P0** | ERD 설계 | AWS 불필요 |
| **P0** | DDL 스크립트 작성 → **git 커밋 필수** | §7.7 — destroy 시 데이터 소실 |
| **P0** | 로컬 MySQL 8.0에서 DDL 검증 | 문법 오류 사전 제거 |
| **P0** | 마이그레이션 도구 선정 (Flyway / Liquibase) | |
| **P1 후** | §12.1 임시 파드로 접속 성공 확인 | |
| **P1 후** | `commondb`에 DDL 실행 → **즉시 WAS 담당에게 통보** | WAS가 대기 중 |
| **P2** | 앱 전용 계정 생성 → WAS 담당에게 전달 | 아래 |
| **P2** | 시드 데이터 투입 | |
| **P2** | 인덱스 검증 (`EXPLAIN`) | |

### 12.3 앱 전용 계정 생성 — `admin` 공유 금지

```sql
CREATE USER 'app_was'@'%' IDENTIFIED BY '<강력한 비밀번호>';
GRANT SELECT, INSERT, UPDATE, DELETE ON commondb.* TO 'app_was'@'%';
FLUSH PRIVILEGES;
```

- `DROP`, `ALTER`, `CREATE` 권한은 주지 않는다. 스키마 변경은 DB팀 전담
- **§13.2의 TLS 강제를 적용한 경우에만** `REQUIRE SSL`을 추가한다. 미적용 상태에서 붙이면 WAS 접속이 실패한다

```sql
-- TLS 강제 적용 시에만
ALTER USER 'app_was'@'%' REQUIRE SSL;
```

---

## §13. 보안 및 암호화 기준

### 13.1 저장 암호화 (at-rest) — ✅ **이미 적용됨**

`modules/rds/main.tf`: `storage_encrypted = true`

AWS 관리형 키(`aws/rds`)를 사용한다. 스냅샷·백업·Read Replica가 전부 암호화를 상속한다.

**CMK(고객 관리형 키) 전환 — 현재 불필요:**

```hcl
resource "aws_kms_key" "rds" {
  description             = "${var.project_name} RDS encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  tags                    = var.common_tags
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# aws_db_instance 에 추가
kms_key_id = aws_kms_key.rds.arn
```

**판단: 토이 프로젝트에는 오버스펙.** AWS 관리형 키로 암호화 요건은 충족된다. CMK는 키 정책 분리·감사 추적·교차계정 스냅샷 공유가 필요할 때 의미가 생긴다. 또한 KMS 키는 삭제 대기가 최소 7일이라 destroy 후 재생성 시 alias 충돌이 발생한다.

> ⏱️ **`storage_encrypted`와 `kms_key_id`는 기존 인스턴스에서 변경 불가하다.** 스냅샷 → 암호화 지정 복사 → 복원 경로를 타야 한다. **apply 전인 지금이 비용 0.**

### 13.2 전송 암호화 (in-transit / TLS) — ⚠️ **미적용. 실제 구멍**

현재 파라미터 그룹이 없어 평문 접속이 허용된다.

`modules/rds/main.tf` 에 추가:

```hcl
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.project_name}-rds-"
  family      = "mysql8.0"

  parameter {
    name  = "require_secure_transport"
    value = "ON"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = var.common_tags
}

# aws_db_instance 에 추가
parameter_group_name = aws_db_parameter_group.this.name
```

> 🚨 **적용 시 WAS 담당에게 반드시 사전 공지한다.** JDBC URL에 TLS 옵션이 없으면 **즉시 전면 접속 실패**한다.
> ```
> jdbc:mysql://<endpoint>:3306/commondb?useSSL=true&requireSSL=true
> ```
> 서버 인증서 검증까지 하려면 `rds-ca-rsa2048-g1` 번들을 이미지에 포함하고 `trustCertificateKeyStoreUrl`을 지정해야 하는데, 뼈대 단계에서는 과하다. **`require_secure_transport = ON` + `useSSL=true`까지가 적정선.**

### 13.3 마스터 비밀번호 — ⚠️ **평문 노출 상태**

현재 `var.db_password`가 tfvars에 평문으로 들어가고 **state에도 평문 저장**된다.

```hcl
# aws_db_instance
# password = var.db_password        <- 반드시 제거 (배타적 인자)
manage_master_user_password = true  # Secrets Manager 자동 생성 + 관리
```

`envs/dev/variables.tf`의 `db_password` 변수와 tfvars 항목도 함께 제거한다.

> **`password`와 `manage_master_user_password`는 동시 지정 불가.** 반드시 기존 줄을 삭제한다.

### 13.4 기타 적용된 보안 통제

| 항목 | 상태 |
|---|---|
| RDS `publicly_accessible = false` | ✅ |
| RDS SG — EKS 노드 SG 출처만 허용 | ✅ |
| DB 서브넷 NAT 라우트 없음 | ✅ |
| ECR `scan_on_push = true` | ✅ |
| ECR `IMMUTABLE` 태그 | ✅ |
| S3 state — 암호화 + 버전관리 + 퍼블릭 차단 | ✅ |
| S3 state `prevent_destroy` | ✅ |

### 13.5 적용 우선순위 — **apply 전 결정 필요**

| 항목 | 권고 | 이유 | 팀 결정 |
|---|---|---|---|
| TLS 강제 (§13.2) | **지금 적용** | 실제로 빠진 유일한 구멍. 나중에 켜면 앱 전면 장애 | 적용 /|
| Secrets Manager (§13.3) | **지금 적용** | state 평문 노출 제거. 나중에 바꾸면 앱 설정 재작업 | ☐ 적용 /|
| CMK (§13.1) | 보류 | 현 요건 대비 오버스펙 | ☐ 사용안함|

> 결정 후 이 표에 체크하고 커밋한다. 결정을 기록하지 않으면 나중에 "왜 안 했지"로 재논의가 반복된다.

---

## §14. 완료 기준(DoD) 체크리스트

### 14.1 인프라 리드

- [ ] `backend-bootstrap` apply 완료, 버킷명 `envs/dev/backend.tf`에 반영
- [ ] §8 선조치 3가지 완료
- [ ] `terraform apply` 완료, 에러 0
- [ ] `terraform output` 전 항목 팀 공유
- [ ] 팀원 전원 `kubectl get nodes` 성공 확인
- [ ] ACM 인증서 상태 **Issued**
- [ ] LB Controller 파드 Running
- [ ] `app` 네임스페이스 생성
- [ ] Cloudflare SSL/TLS = **Full (strict)**
- [ ] WAF / Rate Limit / Bot Fight 활성화
- [ ] Tunnel 생성 + 토큰 BFF 담당 전달
- [ ] Access App 생성 + Policy Action = **Service Auth**
- [ ] Service Token 발급 + OKD팀 전달

### 14.2 EKS팀 (서비스별 공통)

- [ ] `/healthz`, `/readyz` 200 응답
- [ ] 이미지 git SHA 태그로 ECR 푸시 (amd64)
- [ ] Deployment + Service 배포, 파드 Running
- [ ] 하위 서비스 호출 성공
- [ ] 매니페스트 `k8s/` 에 커밋
- [ ] URL 하드코딩 없음 (ConfigMap 주입)

### 14.3 EKS팀 (담당별 추가)

- [ ] **WAS**: RDS 커넥션 수립 로그 확인, Secret으로 자격증명 주입
- [ ] **BFF**: cloudflared 파드 Running + Tunnel 대시보드 **HEALTHY**
- [ ] **Web**: Ingress ADDRESS 필드에 ALB DNS 표시, Target Group **healthy**

### 14.4 DB팀

- [ ] DDL 스크립트 **git 커밋 완료**
- [ ] `commondb` 스키마 생성 완료
- [ ] `app_was` 계정 생성 + 최소 권한 부여
- [ ] WAS 담당에게 자격증명 전달
- [ ] 시드 데이터 투입

### 14.5 전체 흐름 검증

- [ ] **흐름1**: 브라우저 → 앱 도메인 → patient-web 화면 → BFF → WAS → DB 조회 성공
- [ ] **흐름1**: Cloudflare 대시보드에 트래픽 기록 확인 (프록시 경유 증명)
- [ ] **흐름2**: OKD Pod → Access 엔드포인트 → BFF 응답 수신 (JSON, HTML 아님)

---

## §15. 트러블슈팅

### 15.1 최빈 사고 TOP 5 — 각각 반나절씩 날아간다

| 증상 | 원인 | 해결 |
|---|---|---|
| ACM 인증서가 영원히 **Pending Validation** | 검증 CNAME이 **주황 구름(프록시)** 상태 | 회색 구름(DNS only)으로 변경 |
| 브라우저에서 **무한 리다이렉트 루프** | Cloudflare SSL 모드가 **Flexible** | **Full (strict)** 로 변경 |
| ALB Target Group **unhealthy** 영구 지속 | `/healthz` 미구현 또는 경로 불일치 | 엔드포인트 구현 + annotation 경로 일치 확인 |
| OKD에서 **HTML 로그인 페이지** 수신 | Access Policy Action이 `Allow` | **`Service Auth`** 로 변경 |
| 파드 `exec format error` 크래시 | Apple Silicon에서 ARM 이미지 빌드 | `--platform linux/amd64` 지정 후 재빌드 |

### 15.2 진단 명령 모음

```bash
# 노드 상태
kubectl get nodes -o wide

# 파드 이벤트 (ImagePullBackOff, CrashLoopBackOff 원인)
kubectl -n app describe pod <파드명>

# 파드 로그 (재시작 직전 로그)
kubectl -n app logs <파드명> --previous

# Service 엔드포인트 등록 여부 — 비어 있으면 셀렉터 라벨 불일치
kubectl -n app get endpoints

# Ingress / ALB 상태
kubectl -n app describe ingress patient-web

# LB Controller 로그 (ALB 생성 실패 원인)
kubectl -n kube-system logs deploy/aws-load-balancer-controller

# cloudflared 터널 상태
kubectl -n app logs deploy/cloudflared

# 클러스터 내부 통신 테스트
kubectl -n app run tmp --rm -it --image=curlimages/curl --restart=Never -- \
  curl -v http://<서비스>-svc.app.svc.cluster.local:8080/healthz

# DNS 해석 테스트
kubectl -n app run tmp --rm -it --image=busybox --restart=Never -- \
  nslookup bff-svc.app.svc.cluster.local
```

### 15.3 증상별 원인 매핑

| 증상 | 확인 순서 |
|---|---|
| `ImagePullBackOff` | ① 태그 오타 ② ECR 리포지토리 존재 ③ 노드 IAM에 ECR 권한 |
| `CrashLoopBackOff` | ① `logs --previous` ② 아키텍처 불일치 ③ 필수 환경변수 누락 |
| `endpoints` 비어 있음 | Service `selector`와 Pod `labels` 불일치 |
| 서비스 간 호출 timeout | ① 대상 파드 Running ② Service 포트 ③ DNS 이름 오타 |
| RDS 접속 timeout | ① 파드가 `app` 네임스페이스인지 ② RDS SG ingress ③ 엔드포인트 오타 |
| `terraform init` 실패 | `backend.tf`와 부트스트랩 버킷명 불일치 |
| `terraform apply` 권한 오류 | IAM 정책 부족. 리드 계정으로 실행했는지 확인 |

---

## §16. 금지 사항

| # | 금지 행위 | 이유 |
|---|---|---|
| 1 | 인프라 리드 외 인원의 `terraform apply` | 단일 state 손상 |
| 2 | `backend-bootstrap` 재실행 | `prevent_destroy` 충돌 |
| 3 | `*.tfstate`, `*.tfvars` 커밋 | 자격증명 유출 |
| 4 | 이미지 `:latest` 태그 | `IMMUTABLE` 정책 위반, 롤백 추적 불가 |
| 5 | RDS SG에 개인 IP 임시 허용 | 격리 설계 무력화 |
| 6 | DB 서브넷에 `kubernetes.io/*` 태그 부착 | LB Controller가 DB 계층에 ENI 배치 |
| 7 | `admin` 계정을 앱에 직접 사용 | 최소 권한 원칙 위반 |
| 8 | 서비스 URL 코드 하드코딩 | 네임스페이스 변경 시 전면 재빌드 |
| 9 | 뼈대 완성 전 기능 추가 | 통합 지점 불안정화 |
| 10 | Cloudflare 설정을 Terraform으로 이관 | 조건 3 위반, 대시보드 관리 원칙 |

---

## §17. 미결정 사항 및 백로그

**뼈대(G3) 완성 전에는 착수하지 않는다.** 아이디어는 여기 기록만 한다.

### 17.1 결정 필요

| # | 항목 | 선택지 | 기한 |
|---|---|---|---|
| 1 | TLS 강제 적용 여부 (§13.2) | 적용 **apply 전** |
| 2 | Secrets Manager 전환 (§13.3) | 적용| **apply 전** |
| 3 | ECR 태그 정책 (§8.3) | IMMUTABLE| **apply 전** |
| 4 | 내부 흐름 도메인명 | — | P3 전 |

### 17.2 운영 전환 시 필수 변경

| 항목 | 현재 | 변경 후 |
|---|---|---|
| NAT Gateway | 단일 | AZ당 1개 |
| RDS Multi-AZ | `false` | `true` |
| `skip_final_snapshot` | `true` | `false` |
| EKS 엔드포인트 | public + private | private 전용 또는 CIDR 제한 |
| EKS 접근 권한 | 전원 ClusterAdmin | 네임스페이스 스코프 |
| DB 마스터 비밀번호 | 변수 주입 | Secrets Manager |

### 17.3 향후 백로그

- CI/CD 파이프라인 (GitHub Actions → ECR → EKS)
- HPA / Cluster Autoscaler 또는 Karpenter
- 관측성: CloudWatch Container Insights, Prometheus + Grafana
- External Secrets Operator (Secrets Manager 연동)
- Network Policy (파드 간 통신 제어)
- 환경 분리 (`envs/stg`, `envs/prd`) 및 state 분리
- VPC Endpoint (ECR, S3, Secrets Manager) — NAT 비용 절감

---

## §18. 온프레미스(OKD)팀 가이드

> 이 섹션은 **흐름 2**의 시작점을 담당하는 온프레미스 인력을 위한 것이다.
> OKD 팀은 **AWS 계정도, AWS 자격증명도, VPN도 전혀 필요 없다.**

### 18.1 역할 정의 — 무엇을 하고 무엇을 하지 않는가

| 구분 | 내용 |
|---|---|
| ✅ **담당** | OKD 내부망의 Web Pod가 Cloudflare Access 엔드포인트를 **HTTPS로 호출**하는 것 |
| ❌ **비담당** | cloudflared 배포 (EKS 측 BFF 담당이 수행) |
| ❌ **비담당** | Tunnel 생성, Access App/Policy 구성 (인프라 리드가 대시보드에서 수행) |
| ❌ **불필요** | VPN, IPsec, Direct Connect, 인바운드 방화벽 오픈 |

### 18.2 아키텍처상 위치

```
[사내망 OKD]                    [Cloudflare 엣지]              [AWS EKS]
Web Pod ──HTTPS 443──→ Access(Service Token 검증) → Tunnel ──→ cloudflared Pod ──→ bff-svc
        (아웃바운드)                                          (아웃바운드로 사전 연결)
```

**핵심:** 양쪽 모두 **아웃바운드 연결만** 한다. Cloudflare 엣지에서 두 연결이 만난다. 그래서 사내망에 인바운드 포트를 열 필요가 없다 — 이것이 이 아키텍처를 선택한 이유다.

### 18.3 사전 확인 사항 (P0 — 지금 바로 확인 가능)

| # | 확인 항목 | 실패 시 영향 |
|---|---|---|
| 1 | OKD 워커 노드에서 **아웃바운드 443** 허용 여부 | 연결 자체 불가 |
| 2 | 사내 DNS가 **공인 도메인을 해석**하는지 | 호스트명 조회 실패 |
| 3 | 사내 프록시(Forward Proxy) 존재 여부 | 프록시 환경변수 설정 필요 |
| 4 | 프록시가 **TLS MITM 검사**를 하는지 | 사내 CA 인증서를 컨테이너에 주입해야 함 |
| 5 | Pod의 아웃바운드가 **Egress Policy로 제한**되는지 | 예외 규칙 추가 필요 |

```bash
# OKD 노드 또는 테스트 Pod에서 실행
curl -sv https://www.cloudflare.com --max-time 10
nslookup <내부흐름-도메인>
env | grep -i proxy
```

> ⚠️ **1~5번은 인프라 리드의 P1 작업과 무관하게 지금 확인할 수 있다.** 방화벽 정책 변경은 사내 승인 절차상 며칠이 걸릴 수 있으므로 **가장 먼저 착수한다.**

### 18.4 인프라 리드에게 수령할 항목 (P3 시작 시)

| 항목 | 형태 | 용도 |
|---|---|---|
| 내부 흐름 도메인 | `https://internal-xxx.<도메인>` | 호출 대상 URL |
| Service Token **Client ID** | `xxxxx.access` | 인증 헤더 |
| Service Token **Client Secret** | 긴 문자열 | 인증 헤더 |

> 🔒 Secret은 **1회만 표시**된다. 수령 즉시 안전한 곳에 보관하고, 분실 시 재발급이 필요하다.

### 18.5 호출 방식 — Service Token 헤더

```bash
curl -s https://internal-xxx.<도메인>/api/health \
  -H "CF-Access-Client-Id: <CLIENT_ID>" \
  -H "CF-Access-Client-Secret: <CLIENT_SECRET>"
```

**두 헤더 이름은 정확히 이대로여야 한다.** 오타 시 Access가 인증되지 않은 요청으로 처리한다.

### 18.6 OKD 리소스 구성

**Secret 생성 — 이미지에 토큰을 절대 넣지 않는다**

```bash
oc create secret generic cf-access-token \
  --from-literal=CF_ACCESS_CLIENT_ID='<CLIENT_ID>' \
  --from-literal=CF_ACCESS_CLIENT_SECRET='<CLIENT_SECRET>' \
  -n <내부-네임스페이스>
```

**Deployment 주입**

```yaml
spec:
  template:
    spec:
      containers:
        - name: internal-web
          env:
            - name: BFF_BASE_URL
              value: "https://internal-xxx.<도메인>"
            - name: CF_ACCESS_CLIENT_ID
              valueFrom:
                secretKeyRef: { name: cf-access-token, key: CF_ACCESS_CLIENT_ID }
            - name: CF_ACCESS_CLIENT_SECRET
              valueFrom:
                secretKeyRef: { name: cf-access-token, key: CF_ACCESS_CLIENT_SECRET }
```

### 18.7 애플리케이션 구현 요구사항

| # | 요구사항 | 이유 |
|---|---|---|
| 1 | 두 헤더를 **모든 요청**에 부착 | 누락 시 인증 실패 |
| 2 | 토큰을 환경변수로 읽기. **코드/이미지 하드코딩 금지** | 유출 및 로테이션 불가 |
| 3 | 토큰을 **로그에 출력 금지** | 자격증명 유출 |
| 4 | HTTP 타임아웃 설정 (connect 5s / read 30s) | 엣지 경유로 홉이 늘어남 |
| 5 | 재시도는 **2~3회, 지수 백오프** | 무제한 재시도는 Rate Limit 유발 |
| 6 | 응답 `Content-Type` 검증 | 인증 실패 시 HTML이 온다 (§18.8) |

### 18.8 🚨 최빈 실패 — HTML 응답 수신

**증상:** JSON을 기대했는데 Cloudflare 로그인 페이지 HTML이 오거나 302 리다이렉트가 발생한다.

| 원인 | 확인 방법 | 조치 주체 |
|---|---|---|
| Access Policy Action이 `Allow` (`Service Auth` 아님) | 대시보드 확인 | **인프라 리드** |
| 헤더 이름 오타 | `curl -v` 로 요청 헤더 확인 | OKD팀 |
| Client Secret 값 손상 (개행/공백 혼입) | Secret 재생성 | OKD팀 |
| 해당 도메인에 Access App 미적용 | 대시보드 확인 | 인프라 리드 |

```bash
# 진단: 상태코드와 Content-Type만 확인
curl -s -o /dev/null -w "%{http_code} %{content_type}\n" \
  https://internal-xxx.<도메인>/api/health \
  -H "CF-Access-Client-Id: <ID>" \
  -H "CF-Access-Client-Secret: <SECRET>"
```

- `200 application/json` → **정상**
- `302` 또는 `200 text/html` → 위 표대로 원인 추적

### 18.9 사내 프록시 / TLS 검사 환경 대응

프록시가 있는 경우:

```yaml
env:
  - name: HTTPS_PROXY
    value: "http://proxy.internal:3128"
  - name: NO_PROXY
    value: "localhost,127.0.0.1,.svc,.cluster.local"
```

프록시가 TLS MITM 검사를 하는 경우, **사내 CA 인증서를 ConfigMap으로 마운트**하고 언어별 신뢰 저장소에 등록해야 한다. 미조치 시 `certificate verify failed` 로 전부 실패한다.

### 18.10 OKD팀 완료 기준(DoD)

- [ ] 아웃바운드 443 허용 확인
- [ ] 공인 도메인 DNS 해석 확인
- [ ] 프록시 / TLS 검사 여부 파악 및 대응 완료
- [ ] Service Token을 OpenShift Secret으로 생성 (이미지 하드코딩 없음)
- [ ] Web Pod에서 Access 엔드포인트 호출 → **`200 application/json`** 수신
- [ ] BFF 응답 데이터가 화면에 정상 렌더링
- [ ] 타임아웃 / 재시도 정책 적용
- [ ] 토큰이 로그에 남지 않음 확인

### 18.11 EKS팀과의 인터페이스 합의

OKD Web Pod가 호출하는 API 스펙은 **BFF 담당과 사전 합의**한다. 흐름 2는 `bff-svc`로 직결되므로, 외부 흐름(`patient-web` 경유)과 **동일한 BFF API를 공유할지 별도 엔드포인트를 둘지**를 P0 단계에서 결정해야 한다.

| 선택지 | 장점 | 단점 |
|---|---|---|
| 공통 API 공유 | 개발량 최소 | 내부 전용 기능 추가 시 권한 분기 필요 |
| 내부 전용 경로 분리 (`/internal/*`) | 권한 경계 명확 | BFF 라우팅 추가 작업 |

> **뼈대 단계에서는 공통 API 공유를 권장한다.** 두 흐름의 소통 자체를 증명하는 것이 목표이므로, 경로 분리는 §17 백로그로 넘긴다.

---

## 문서 갱신 규칙

| 상황 | 조치 |
|---|---|
| 구조·버전·표준 변경 | 이 문서를 **먼저** 수정하고 PR |
| 새 트러블슈팅 발견 | §15에 추가 |
| 결정 사항 확정 | §13.5 또는 §17.1 표에 기록 |
| 문서와 코드 불일치 발견 | **문서가 틀린 것.** 즉시 PR |

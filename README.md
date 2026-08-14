# Hybrid Toy Project — 기술 가이드라인 v4.0

> **이 문서는 프로젝트의 단일 진실 공급원(Single Source of Truth)이다.**
> 문서와 코드가 다르면 **문서가 틀린 것**이다. 발견 즉시 PR로 문서를 고친다.

| 항목 | 값 |
|---|---|
| 문서 버전 | **v4.0 (최종)** |
| 대상 환경 | `dev` (단일 환경) |
| AWS 리전 | `ap-northeast-2` (서울) |
| 프로젝트 식별자 | `hybrid-toy` |
| 상태 | **G1 → G3 완료 + 관측성 도입 완료** |
| 하위 문서 | `구축설명서-v2.0.md` |

---

## 이 문서의 범위

두 문서는 역할이 다르다. 중복 기술하지 않는다.

| | **README (이 문서)** | **구축설명서** |
|---|---|---|
| 다루는 것 | 무엇을 약속했는가 · 왜 그렇게 설계했는가 · 무엇이 금지인가 | 누가 무엇을 어떤 순서로 만들었는가 |
| 내용 | 아키텍처, 계약, 표준, 설계 판단, 보안 기준, 트러블슈팅, 결정 로그 | 산출물 트리, 팀별 실행 절차, 검증 스크립트, DoD 체크리스트, 배치 이력, 날짜 |
| 성격 | **시간에 독립적** — 계약은 실행 순서가 바뀌어도 유효하다 | **시간에 종속적** — 실행의 기록 |
| 충돌 시 | **이 문서가 이긴다** | — |

> 버전 변경 요약, 게이트 통과 일자, 배포 이력, 체크리스트, P0~P3 실행 기록은 전부 구축설명서에 있다.
> 이 문서에서 `✅ v3.x` 같은 개정 표기를 제거했다. **현재 유효한 계약만 남긴다.**

**구 버전(v3.2) 참조 번호를 쓰는 코드 주석·스크립트가 있다면 [부록 A 번호 매핑](#부록-a-문서-번호-매핑)을 본다.**

---

## 목차

- [§0. 프로젝트 개요 및 구축 결과](#0-프로젝트-개요-및-구축-결과)
- [§1. 시스템 구성](#1-시스템-구성)
- [§2. 네트워크 설계](#2-네트워크-설계)
- [§3. 리포지토리 구조 및 소유권](#3-리포지토리-구조-및-소유권)
- [§4. 협업 규칙](#4-협업-규칙)
- [§5. 기술 스택 및 버전 고정](#5-기술-스택-및-버전-고정)
- [§6. 표준 및 계약](#6-표준-및-계약)
- [§7. 설계상 핵심 판단](#7-설계상-핵심-판단)
- [§8. 보안 및 암호화 기준](#8-보안-및-암호화-기준)
- [§9. 데이터베이스 운영 계약](#9-데이터베이스-운영-계약)
- [§10. 관측성(Observability)](#10-관측성observability)
- [§11. 트러블슈팅 지식베이스](#11-트러블슈팅-지식베이스)
- [§12. 반복 실패 패턴과 표준 대응](#12-반복-실패-패턴과-표준-대응)
- [§13. 금지 사항](#13-금지-사항)
- [§14. 온프레미스(OKD) 인터페이스 계약](#14-온프레미스okd-인터페이스-계약)
- [§15. 확정 결정 로그](#15-확정-결정-로그)
- [§16. 백로그 및 운영 전환 요건](#16-백로그-및-운영-전환-요건)
- [§17. 확정 인프라 식별자](#17-확정-인프라-식별자)
- [부록 A. 문서 번호 매핑](#부록-a-문서-번호-매핑)

---

## §0. 프로젝트 개요 및 구축 결과

### 0.1 목표

온프레미스(OKD)와 AWS 클라우드를 Cloudflare로 연결하는 하이브리드 구조의 **최소 동작 뼈대**를 구축한다.

### 0.2 반드시 구성해야 하는 2개 흐름

**흐름 1 — 외부 사용자 (환자)**

```
환자 Browser
  → Cloudflare (WAF / Rate Limit / DDoS)
  → ALB (ACM TLS 종단)
  → /api/bff/patient/** → bff-svc → was-svc → RDS
  → /                   → patient-web-svc
```

**흐름 2 — 내부 사용자 (직원)**

```
직원 Browser
  → OKD Web Pod (서버사이드 프록시, 사내망)
  → Cloudflare Access (Service Token 인증)
  → Cloudflare Tunnel
  → cloudflared Pod → bff-svc → /api/bff/staff/** → was-svc → RDS
```

> **직원 API는 외부 ALB에 등록하지 않는다.** ALB 규칙에 `/api/bff/staff`가 존재하면 설계 위반이다.

### 0.3 스코프 원칙

> **이 2개 흐름 "만" 먼저 완성한다. 그 외 일체의 디테일은 완성 후 추가한다.**

기능 추가 제안은 §16 백로그에 기록만 하고 착수하지 않는다.

### 0.4 전제 조건

| # | 조건 |
|---|---|
| 1 | 온프레미스 OKD 환경은 **이미 구성 완료** 상태 |
| 2 | Cloudflare 설정은 **대시보드 수동 작업** (cloudflared Pod 제외). Terraform 관리 대상 아님 |
| 3 | Git repo 1개를 전원이 공유. `terraform apply`는 **인프라 리드 1인 전담** |
| 4 | 팀별 state 분리 없음. 단일 state 운영 |
| 5 | S3 버킷은 **필수 옵션만** 사용 |

### 0.5 페이즈 구조와 임계 경로

| 페이즈 | 내용 | 게이트 |
|---|---|---|
| **P0** | AWS 불필요 작업 — 전 팀 병렬 | — |
| **P1** | 인프라 리드 단독 apply | **G1** — 인프라 자동화 완료 |
| **P2** | 3팀 병렬 개발 + 배포 | **G2** — 흐름1(환자) 완성 |
| **P3** | 흐름2(내부 터널) 연결 | **G3** — 전체 완료 |

```
                  ┌─→ ECR ─────────────────────────────┐
인프라 apply ─G1─┤                                      ├─→ 이미지 빌드/푸시 (전원 즉시 병렬)
                  └─→ EKS / RDS                         ┘
                        │
              DB 스키마 ─┴─→ WAS ─→ BFF ─→ Web ─→ Ingress ─G2─→ 흐름1 완료
                                      └─→ cloudflared ────G3─→ 흐름2 완료
```

**`DB → WAS → BFF → Web`이 임계 경로다.**

- 이미지 빌드·푸시는 4명 전원 **즉시 병렬** 가능하다. **배포 순서만 직렬이다.**
- 하위 서비스가 없으면 상위가 헬스체크에 실패해 무한 재시작한다.
- WAS 담당은 스키마 대기로 멈추지 않는다. 커넥션 수립만 확인되면 다음으로 넘어간다.

### 0.6 구축 결과

**계약대로 구현·배포·검증 완료.** 절차와 일자는 구축설명서에 있다.

| 구간 | 검증 결과 |
|---|---|
| DB | 상병코드 마스터 14,283 + 동의어 37,543, `app_was` 최소 권한 + `REQUIRE SSL` |
| WAS | `verify-was.ps1` **38/38** |
| BFF | `verify-bff.ps1` **45/45** |
| 흐름1 (환자, HTTPS) | `verify-flow1.ps1` **24/24** + 브라우저 실동작 |
| 흐름2 (직원, Tunnel) | `verify-flow2.ps1` **29/29** |
| 관측성 | Container Insights 대시보드 + 로그 4종 그룹 (§10) |

**실증된 설계 판단**

| 설계 | 증거 |
|---|---|
| DB 제약이 본선, 앱 체크는 보조 | `slot_taken`·`duplicate_booking`·`duplicate_prescription`·`patient_exists` 4종이 전부 UNIQUE 위반 → 계약 코드 변환으로 동작 |
| 취소 시 NULL이 되는 생성 컬럼 | 취소 후 동일 슬롯 재예약 성공 |
| 상병명 스냅샷 | 마스터 UPSERT 후에도 `chart.icd_name_snapshot`이 발급 시점 값 유지 |
| 3중 권한 방어 | BFF 401 → `ActorHeaderFilter` 403 → `ChartService` NURSE 403 |
| 전달수단 바인딩 | 직원 JWT를 쿠키에 실으면 **서명은 통과하고 바인딩만이 막는다** |
| `X-Actor-*` 제거 | 위조 헤더 주입 → 401 |
| `/readyz` 종속 차단 | BFF `/readyz`가 WAS 상태를 보지 않아 WAS 재배포 중에도 BFF Ready 유지 |
| `maxUnavailable: 0` | 롤아웃 전 구간에서 정상 파드 ≥ 1 |
| Access `Service Auth` | 토큰 없음/오류 → 403, 올바른 토큰 → 401 JSON |
| `X-Trace-Id` 연속성 | BFF → WAS 전 구간 동일 값 |

**범위 밖으로 이관한 것**: OKD Web 애플리케이션 구현(프로젝트 기간 제약), §16 백로그 전체(NetworkPolicy·mTLS·CI/CD·HPA·Refresh Token 등).

---

## §1. 시스템 구성

### 1.1 애플리케이션 서비스 (EKS 배포 대상)

| 서비스 | ECR 리포지토리 | K8s Service | 클러스터 내 DNS | 포트 | 담당 |
|---|---|---|---|---|---|
| `patient-web` | `hybrid-toy/patient-web` | `patient-web-svc` | `patient-web-svc.app.svc.cluster.local` | 8080 | EKS팀 — Web (`kusweb`) |
| `bff` | `hybrid-toy/bff` | `bff-svc` | `bff-svc.app.svc.cluster.local` | 8080 | EKS팀 — BFF (`kusbff`) |
| `was` | `hybrid-toy/was` | `was-svc` | `was-svc.app.svc.cluster.local` | 8080 | EKS팀 — WAS (`kuswas`) |
| `cloudflared` | (공식 이미지) | 없음 (아웃바운드 전용) | — | — | EKS팀 — BFF (`kusbff`) |

- 네임스페이스: **`app`** (cloudflared 포함 전부 동일)
- Service 타입: 전부 **ClusterIP**. 외부 노출은 Ingress 하나뿐
- `cloudflared`는 Cloudflare 엣지로 **아웃바운드 연결만** 하므로 Service·Ingress 불필요

### 1.2 서비스 간 호출 관계

```
[외부] ALB ─ /api/bff/patient ──────────────────┐
           └ /                → patient-web-svc │
                                                ├─→ bff-svc:8080 ─→ was-svc:8080 ─→ RDS:3306
[내부] cloudflared Pod ─────────────────────────┘
```

- `bff`는 **외부·내부 두 흐름의 공통 수렴점**이다.
- `was`만 RDS에 접근한다. `bff`·`patient-web`은 DB 자격증명을 갖지 않는다.
- `patient-web`은 `/api/bff/staff/**`를 **프록시하지 않는다.** 해당 요청은 404를 반환한다.

### 1.3 AWS 인프라 리소스

| 리소스 | 이름 / 식별자 | Terraform | 담당 |
|---|---|---|---|
| VPC | `hybrid-toy-vpc` | ✅ `modules/network` | 인프라 리드 |
| Subnet (Public ×2) | ALB 배치용 | ✅ | 인프라 리드 |
| Subnet (Private ×2) | EKS 워커 배치용 | ✅ | 인프라 리드 |
| Subnet (Database ×2) | RDS 전용 | ✅ | 인프라 리드 |
| NAT Gateway ×1 | 단일 NAT | ✅ | 인프라 리드 |
| EKS Cluster | `hybrid-toy-eks` | ✅ `modules/eks` | 인프라 리드 |
| EKS Managed Node Group | `default` (t3.medium ×2) | ✅ | 인프라 리드 |
| IRSA Role (LBC) | `hybrid-toy-eks-lbc-irsa` | ✅ | 인프라 리드 |
| ECR ×3 | §1.1 | ✅ `modules/ecr` | 리드 생성 / EKS팀 사용 |
| RDS (MySQL 8.0) | `hybrid-toy-rds` | ✅ `modules/rds` | 리드 생성 / DB팀 운영 |
| ACM 인증서 | `var.alb_domain_name` | ✅ `envs/dev` | 인프라 리드 |
| S3 (tfstate) | `hybrid-toy-tfstate-kuspital` | ✅ `backend-bootstrap` | 인프라 리드 |
| **ALB** | Ingress가 동적 생성 | ❌ **K8s Ingress** | EKS팀 — Web |
| **IAM Role (CW Agent)** | `hybrid-toy-eks-cwagent-role` | ❌ **CLI 생성** | 인프라 리드 (§10) |

> ⚠️ **ALB는 Terraform이 만들지 않는다.** §7.1 참조.
> ⚠️ **CloudWatch용 IAM Role은 state 밖에 있다.** `terraform destroy`가 지우지 않는다. §10.5 참조.

### 1.4 클러스터 애드온

| 애드온 | 설치 주체 | 방식 | 비고 |
|---|---|---|---|
| VPC CNI | Terraform | EKS Addon | **`before_compute = true` 필수** |
| EKS Pod Identity Agent | Terraform | EKS Addon | **`before_compute = true` 필수** |
| CoreDNS | Terraform | EKS Addon | 노드 기동 후 |
| kube-proxy | Terraform | EKS Addon | 노드 기동 후 |
| AWS Load Balancer Controller | 인프라 리드 | Helm (수동, 버전 고정) | Ingress → ALB 변환 |
| **Amazon CloudWatch Observability** | 인프라 리드 | EKS Addon (CLI) | Pod Identity 인증. §10 |

> 📌 **노드 부팅 시점에 필요한 애드온은 전부 `before_compute = true`.** 미지정 시 클러스터가 CNI 없이 생성되어 노드가 영구 `NotReady` → 33분 타임아웃 후 `NodeCreationFailure`.

```hcl
addons = {
  coredns    = {}
  kube-proxy = {}
  vpc-cni                = { before_compute = true }   # 필수
  eks-pod-identity-agent = { before_compute = true }   # 필수
}
```

### 1.5 Cloudflare 리소스 (전부 대시보드 수동)

| 리소스 | 용도 | 흐름 | 담당 |
|---|---|---|---|
| DNS Zone | 도메인 관리 | 공통 | 인프라 리드 |
| DNS Record (ACM 검증 CNAME) | 인증서 발급 | 1 | 인프라 리드 |
| DNS Record (`www` → ALB) | 프록시 경유 | 1 | 인프라 리드 |
| WAF / Rate Limit / Bot Fight | 외부 트래픽 필터 | 1 | 인프라 리드 |
| SSL/TLS = Full (strict) | 종단간 TLS | 1 | 인프라 리드 |
| Zero Trust — Tunnel | 내부망 → EKS | 2 | 인프라 리드 |
| Zero Trust — Access Application | 내부 엔드포인트 보호 | 2 | 인프라 리드 |
| Zero Trust — Service Token | OKD 인증 수단 | 2 | 인프라 리드 → OKD팀 |

> 🚨 **Access Policy의 Action은 반드시 `Service Auth`.** `Allow`로 두면 Service Token을 보내도 IdP 로그인을 요구해 OKD Pod가 HTML을 받는다.
> 🚨 **`staff-api` DNS 레코드를 미리 만들지 않는다.** Tunnel Public Hostname 등록 시 자동 생성되며, 수동 레코드가 있으면 충돌한다.
> 🚨 **ACM 검증 CNAME은 ⚪ 회색(DNS only).** 🟠 주황(프록시)이면 인증서가 영구 `Pending Validation`.

---

## §2. 네트워크 설계

### 2.1 서브넷 구성 — 총 6개 (3-tier × 2 AZ)

VPC CIDR `10.0.0.0/16`, AZ: `ap-northeast-2a`, `ap-northeast-2c`

| Tier | CIDR | 배치 대상 | 인터넷 경로 | 개수 |
|---|---|---|---|---|
| **Public** | `10.0.0.0/24`, `10.0.1.0/24` | ALB | IGW | 2 |
| **Private** | `10.0.10.0/24`, `10.0.11.0/24` | EKS 워커, 전체 파드, cloudflared | NAT (아웃바운드 전용) | 2 |
| **Database** | `10.0.20.0/24`, `10.0.21.0/24` | RDS | **없음 (완전 격리)** | 2 |

### 2.2 서브넷 태그 정책

| Tier | 태그 | 이유 |
|---|---|---|
| Public | `kubernetes.io/role/elb = 1`<br>`kubernetes.io/cluster/hybrid-toy-eks = shared` | LBC가 외부 ALB 배치 후보로 인식 |
| Private | `kubernetes.io/role/internal-elb = 1`<br>`kubernetes.io/cluster/hybrid-toy-eks = shared` | 내부 LB 배치 후보 |
| Database | `Tier = database` **만** | ⚠️ `kubernetes.io/*` 태그를 넣으면 LBC가 DB 계층에 ELB ENI를 배치할 수 있다 |

격리는 **라우트 테이블과 태그 양쪽에서** 성립한다. Public 2개가 서로 다른 AZ이므로 `internet-facing` ALB 배치 요건(최소 2 AZ)도 충족한다.

### 2.3 RDS 접근 통제 — 삼중 방어

| 계층 | 통제 수단 |
|---|---|
| 네트워크 | DB 전용 서브넷 + 전용 RT (NAT 라우트 없음) |
| 방화벽 | SG — EKS 노드 SG 출처의 3306만 허용 |
| 접근성 | `publicly_accessible = false` |

**결과: 로컬 PC에서 RDS 직접 접속 불가.** DB팀은 §9.1 경로를 사용한다.

### 2.4 서브넷 분리 근거

| 근거 | 설명 |
|---|---|
| Defense in depth | SG 규칙 하나 잘못 수정해도 서브넷 경계가 2차 방어선 |
| IP 고갈 방지 | VPC CNI는 파드마다 ENI 보조 IP를 소비한다. 워커가 `/24`를 잠식하면 RDS 확장 시 IP 부족 |
| 감사 대응 | 의료 도메인. 데이터 계층 네트워크 분리는 사실상 필수 요건 |

> ⏱️ apply 후 서브넷 그룹을 바꾸면 `aws_db_subnet_group` 교체 → **RDS 재생성**이 트리거된다. 이 구조는 apply 전에 확정되어야 한다.

### 2.5 DB 서브넷에 NAT 라우트를 붙이지 않은 이유

RDS는 아웃바운드 인터넷이 불필요하다. 향후 S3 export나 Lambda 연동이 필요해지면 **NAT가 아니라 VPC Endpoint**를 추가한다.

```hcl
create_database_subnet_route_table = true    # 격리 성립
create_database_subnet_group       = false   # §7.3 중복 방지
```

> ⚠️ **두 인자는 역할이 다르다.** 이름이 비슷하다는 이유로 하나만 보고 판단하지 않는다.

---

## §3. 리포지토리 구조 및 소유권

```
repo/
├── README.md                      # 이 문서 — 전원 필독
├── 구축설명서-v2.0.md              # 산출물·역할·실행순서·검증
├── .gitignore
│
├── infra/
│   ├── backend-bootstrap/         # [리드] 최초 1회만. S3 state 버킷
│   ├── envs/dev/                  # [리드] 유일한 apply 지점
│   └── modules/
│       ├── network/               # [리드]  VPC, 3-tier Subnet, NAT
│       ├── eks/                   # [리드]  EKS, NodeGroup, IRSA
│       ├── ecr/                   # [EKS팀] 리포지토리 정의
│       └── rds/                   # [DB팀]  RDS, SG, SubnetGroup, ParameterGroup
│
├── db/                            # [DB팀]  DDL / GRANT / SEED  ★git 커밋 필수
│   ├── 01_schema.sql
│   ├── 02_grants.sql
│   ├── 03_seed.sql
│   ├── 04_icd_seed.sql            # KCD 상병코드 적재 (생성물)
│   ├── raw/data.json              # 공공데이터 원본 (19MB, 47,798행)
│   └── tools/
│       ├── gen-bcrypt.ps1
│       └── convert-icd.ps1        # data.json → 04_icd_seed.sql
│
├── apps/
│   ├── was/                       # [WAS]   Spring Boot 4.1.0
│   ├── bff/                       # [BFF]   Spring Boot 4.1.0
│   └── patient-web/               # [Web]   SPA + nginx
│
├── local/docker-compose.yml       # [EKS팀] 로컬 통합 검증
│
├── k8s/                           # [EKS팀] 매니페스트. Terraform 관리 대상 아님
│   ├── namespace.yaml
│   ├── common/configmap.yaml
│   ├── was/{deployment,service,secret.example}.yaml
│   ├── bff/{deployment,service,configmap,secret.example}.yaml
│   ├── patient-web/{deployment,service,configmap}.yaml
│   ├── cloudflared/{deployment,secret.example}.yaml
│   └── ingress/patient-web-ingress.yaml
│
├── monitoring/                    # [리드] CloudWatch 애드온 구성값 (§10)
│   ├── cw-trust.json
│   └── cw-addon-config.json
│
└── scripts/                       # [EKS팀/리드] 빌드·배포·검증
```

### 3.1 디렉토리별 편집 권한

| 경로 | 편집 가능 | 비고 |
|---|---|---|
| `infra/backend-bootstrap/` | 인프라 리드 | **apply는 최초 1회. 재실행 절대 금지** |
| `infra/envs/dev/` | 인프라 리드 | 모듈 조립 및 apply 지점 |
| `infra/modules/network`, `eks` | 인프라 리드 | |
| `infra/modules/ecr` | EKS팀 | PR 필요 |
| `infra/modules/rds` | DB팀 | PR 필요 |
| `db/` | DB팀 | |
| `apps/was` | WAS 담당 | |
| `apps/bff` | BFF 담당 | |
| `apps/patient-web` | Web 담당 | |
| `k8s/<서비스>/` | 해당 서비스 담당 | |
| `k8s/ingress/` | Web 담당 | BFF 담당 리뷰 필수 (경로 규칙 공유) |
| `k8s/cloudflared/` | BFF 담당 | |
| `monitoring/` | 인프라 리드 | |

### 3.2 `app` 네임스페이스 소유권

`k8s/namespace.yaml` 이 **유일한 정의**다. PSA 라벨·LimitRange·ResourceQuota를 포함한다.

> `kubectl create namespace` 로 만든 리소스는 `last-applied-configuration` 이 없어 첫 `apply` 에서 충돌한다. `--server-side` 로 흡수한다.

---

## §4. 협업 규칙

### 4.1 Terraform 운영 규칙

| 규칙 | 내용 |
|---|---|
| **apply 권한** | **인프라 리드 1인 전담.** 다른 팀원은 `terraform apply` 실행 금지 |
| **plan 권한** | 전원 가능 |
| **state** | 단일 state (`envs/dev/terraform.tfstate`) |
| **Lock** | S3 Native Locking (`use_lockfile = true`). DynamoDB 미사용 |
| **작업 흐름** | 모듈 수정 → PR → 리드 리뷰 → merge → 리드가 apply |
| **커밋 금지** | `*.tfstate`, `*.tfvars`, `.terraform/`, `*.pem`, `*.key` |
| **apply 직전** | `aws sts get-caller-identity --query Arn --output text` → `user/team03` 확인 |

**apply 전 필수 절차**

```powershell
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

> `terraform apply` 단독 실행 금지. plan 파일을 거쳐야 검토한 내용과 실제 적용이 일치한다.
> `validate` 는 **문법만** 본다. plan 육안 검토가 유일한 방어선이다.
> 리포 루트에서 `validate` 하면 검증 대상 0개로 `Success!` 가 뜬다. `envs/dev` 와 `backend-bootstrap` 에서 **각각** 실행한다. 재귀는 `fmt -recursive` 뿐이다.

**S3 state 버킷 — 절대 규칙**

- 수동 삭제 금지. 버전 이력이 포렌식 복구 수단이다.
- S3 backend가 이미 존재하는 상태에서 `terraform init -backend=false` 를 쓰지 않는다.
- `backend-bootstrap` 재실행 금지 (`prevent_destroy` 충돌).

### 4.2 Git 규칙

| 항목 | 규칙 |
|---|---|
| 브랜치 | `feature/<team>-<내용>` (예: `feature/bff-nimbus-jwt`) |
| 커밋 | `[team] 내용` (예: `[db] commondb DDL 확정`) |
| PR | 본인 담당 디렉토리 외 파일 변경 시 해당 팀 리뷰 필수 |
| `envs/dev/main.tf` | 인프라 리드만 수정 |

### 4.3 시크릿 취급 — 전 팀 공통

| 항목 | 규칙 |
|---|---|
| 커밋 | 실제 값이 담긴 Secret 매니페스트 커밋 금지. `*.secret.example.yaml`만 커밋 |
| 전달 | 채팅·이슈·PR 본문에 붙여넣지 않는다 |
| 로그 | 비밀번호·JWT·Service Token·Tunnel Token을 로그에 출력하지 않는다 |
| 인증 API | 요청/응답 body 전체 로깅을 적용하지 않는다 |
| 식별자 입력 | ARN·도메인·토큰은 **렌더링된 텍스트를 복사하지 않는다.** §12.2 |

> ⚠️ 관측성 도입 이후 애플리케이션 로그는 **CloudWatch Logs에 영속 저장된다**(§10). 로그 규정 위반은 이제 즉시 외부화된다.

### 4.4 문서 갱신 규칙

| 상황 | 조치 |
|---|---|
| 구조·버전·표준 변경 | 이 문서를 **먼저** 수정하고 PR |
| 새 트러블슈팅 발견 | §11에 추가 |
| 결정 사항 확정 | **§15 표에 기록** |
| 실행 절차·산출물 변경 | 구축설명서 수정 |
| 문서와 코드 불일치 발견 | **문서가 틀린 것.** 즉시 PR |

---

## §5. 기술 스택 및 버전 고정

**임의 변경 금지.** 변경이 필요하면 §15에 결정을 기록하고 PR한다.

### 5.1 인프라

| 항목 | 고정 버전 | 근거 |
|---|---|---|
| Terraform | `>= 1.10.0` | S3 native locking(`use_lockfile`) 최소 버전 |
| AWS Provider | `~> 6.0` (해석 `6.58.0`) | `.terraform.lock.hcl` 고정 |
| `terraform-aws-modules/eks/aws` | `~> 21.0` (해석 `21.24.2`) | v21 = Cluster Access Management 전환 완료 |
| `terraform-aws-modules/vpc/aws` | `~> 5.0` (해석 `5.21.0`) | `database_subnets` 1급 인자 |
| `terraform-aws-modules/iam` | `~> 5.0` (해석 `5.60.0`) | IRSA 서브모듈 |
| Kubernetes (EKS) | **`1.35`** | 표준 지원 구간. **1.33은 2026-07-29 표준 지원 종료 → $0.60/h (6배)** |
| MySQL (RDS) | `8.0` | 파라미터 그룹 `family = mysql8.0` 과 정합 |
| AWS LB Controller Chart | **`3.5.0`** | `--version` 고정. 부동 시 재설치자마다 다른 버전 유입 |
| CloudWatch Observability Addon | **`v6.5.0-eksbuild.1`** | Pod Identity(3.1.0+) · autoMonitor(5.0.0+) 요구 충족 |
| 노드 인스턴스 | `t3.medium` × 2 (min 1 / max 3) | 토이 규모 |
| RDS 인스턴스 | `db.t3.micro`, 20GB | 토이 규모 |

### 5.2 DynamoDB Lock Table을 쓰지 않는 이유

Terraform 1.10부터 S3 backend가 **native locking**을 지원한다. 별도 DynamoDB는 legacy이며, "S3 필수 옵션만 사용" 조건에 부합한다.

**S3 state 버킷 옵션 — 3개만:** Versioning / SSE-S3(AES256) / Public Access Block(4종). Object Lock·Replication·Lifecycle은 오버스펙.

### 5.3 애플리케이션

| 항목 | 고정 버전 | 근거 |
|---|---|---|
| Java | **25** (LTS) | Spring Boot 4.x 1급 지원 |
| 컨테이너 JDK | **Amazon Corretto 25** | AWS 환경 정합 |
| Spring Boot | **4.1.0** | 2026-06-10 GA. 활성 지원 ~2027-07-31. **3.5는 2026-06-30 EOL** |
| Spring Framework | 7.x | Boot 4.1.0 BOM이 결정. 직접 지정 금지 |
| Spring Security | 7.x | Boot BOM |
| Gradle | **9.5.1** | 9.7.0(2026-08-07 릴리스)은 채택하지 않는다 |
| JSON | **Jackson 3** | Boot 4 기본 |
| JWT | **Nimbus JOSE+JWT `10.9.1`** | **Boot 4.1 BOM이 관리하지 않는다.** 명시 핀 필수 |
| MySQL 드라이버 | `com.mysql:mysql-connector-j` (Boot BOM) | 버전 직접 지정 금지 |
| 컨테이너 플랫폼 | **`linux/amd64`** | 노드가 x86_64. 미지정 시 `exec format error` |
| WAS/BFF 런타임 베이스 | `amazoncorretto:25-alpine` + digest 핀 | |
| patient-web 베이스 | `nginxinc/nginx-unprivileged:1.27-alpine` + digest 핀 | **기본 리슨 포트 8080 · non-root** — §6.1과 정확히 일치 |
| cloudflared | `cloudflare/cloudflared` + digest 핀 | `:latest` 금지 (§13-5) |

**BFF starter 구성** — `starter-web` + `starter-security` + `starter-validation` + **`starter-restclient`**.
`starter-data-jpa` 는 **의도적으로 넣지 않는다.** §6.5의 "BFF DB 직접 접근 금지"를 의존성 차원에서 강제한다.

### 5.4 베이스 이미지 digest

> ⚠️ 이 표에서 값을 **복사해 쓰지 않는다.** 렌더링된 마크다운 복사는 조용한 절단을 일으킨다(§12.2). 기록·대조용이며, 실제 치환은 `docker inspect` 출력을 쓴다.

| 이미지 | digest |
|---|---|
| `amazoncorretto:25-alpine` | `sha256:027310590da693629c2cf704d2f87e9359c33ee2f02bcaa777680b2f4b94f4c7` |
| `nginxinc/nginx-unprivileged:1.27-alpine` | `sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0` |
| `cloudflare/cloudflared` | 배포 시점 조회값 (구축설명서 배포 이력 참조) |

```powershell
docker pull nginxinc/nginx-unprivileged:1.27-alpine
docker inspect --format='{{index .RepoDigests 0}}' nginxinc/nginx-unprivileged:1.27-alpine
```

> 🔒 **태그는 움직이고, 움직인 사실은 장애로만 드러난다.** `stable-alpine` 대신 `1.27-alpine` 을 쓰는 이유는 태그가 움직이지 않아 digest 재확인 주기를 예측 가능하게 만들기 때문이다.

### 5.5 버전 표의 유통기한

> **§5는 시간에 종속된다.** 초안이 고정한 Kubernetes `1.33` 은 작성 시점엔 옳았으나 apply 시점엔 확장 지원 구간이었다. 월 $73 → $438.
> **표를 믿되, apply/빌드 직전에 다시 확인한다.**

---

## §6. 표준 및 계약

> **계약이 코드보다 위다.** 이 절과 다르게 구현했으면 코드가 틀린 것이다.

### 6.1 컨테이너 표준

| 항목 | 표준 |
|---|---|
| 컨테이너 포트 | **8080** (3개 서비스 전부) |
| K8s Service 포트 | **8080** → targetPort 8080 |
| Liveness | `GET /healthz` → 200 |
| Readiness | `GET /readyz` → 200 |
| 이미지 태그 | **git short SHA** (`git rev-parse --short HEAD`) |
| 실행 사용자 | **non-root** |
| 빌드 플랫폼 | `--platform linux/amd64` |

**엔드포인트 의미 — 서비스마다 다르다**

| 서비스 | `/healthz` | `/readyz` |
|---|---|---|
| `was` | 프로세스 생존 | **DB 커넥션 확인** |
| `bff` | 프로세스 생존 | 자체 기동 완료 (WAS 상태에 종속시키지 않는다) |
| `patient-web` | 정적 200 | 정적 200 |

> ⚠️ `/readyz`를 하위 서비스 상태에 종속시키면 **장애가 상위로 전파**된다. BFF의 `/readyz`는 WAS를 확인하지 않는다(§7.9).
> ⚠️ `/healthz` 미구현 시 ALB Target Group이 **영구히 unhealthy**로 남는다. 대표적 반나절 소모 사고다.

### 6.2 환경변수 계약

| 서비스 | 환경변수 | 값 | 주입 |
|---|---|---|---|
| `patient-web` | `BFF_BASE_URL` | `http://bff-svc.app.svc.cluster.local:8080` | ConfigMap |
| `bff` | `WAS_BASE_URL` | `http://was-svc.app.svc.cluster.local:8080` | ConfigMap |
| `bff` | `JWT_ISSUER` | `hybrid-toy-bff` | ConfigMap |
| `bff` | `JWT_AUDIENCE` | `hybrid-toy-api` | ConfigMap |
| `bff` | `PATIENT_JWT_TTL` | `30m` | ConfigMap |
| `bff` | `STAFF_JWT_TTL` | `8h` | ConfigMap |
| `bff` | `JWT_SIGNING_KEY` | (리드 발급, 32바이트 이상) | **Secret `bff-secret`** |
| `was` | `DB_HOST` | RDS 엔드포인트 | ConfigMap |
| `was` | `DB_PORT` | `3306` | ConfigMap |
| `was` | `DB_NAME` | `commondb` | ConfigMap |
| `was` | `TZ` | `Asia/Seoul` | ConfigMap |
| `was` | `DB_USER` | `app_was` | **Secret `was-secret`** |
| `was` | `DB_PASSWORD` | (DB팀 발급) | **Secret `was-secret`** |
| `cloudflared` | `TUNNEL_TOKEN` | (리드 발급) | **Secret `cloudflared-secret`** |

> **하드코딩 금지.** URL을 코드에 박으면 네임스페이스 변경 시 전 서비스를 재빌드해야 한다.
> `JWT_AUDIENCE` 는 `hybrid-toy-api` 다. `hybrid-toy` 로 쓴 코드가 실제로 있었다 — 배포 전 대조 대상이다.

### 6.3 리소스 명명 규칙

| 대상 | 규칙 | 예시 |
|---|---|---|
| AWS 리소스 | `hybrid-toy-<리소스>` | `hybrid-toy-eks` |
| ECR 리포지토리 | `hybrid-toy/<서비스>` | `hybrid-toy/bff` |
| K8s Deployment | `<서비스>` | `bff` |
| K8s Service | `<서비스>-svc` | `bff-svc` |
| K8s Secret | `<서비스>-secret` | `bff-secret` |
| K8s ConfigMap | `<서비스>-config` | `bff-config` |

### 6.4 공통 태그 · 파드 리소스 계약

```hcl
Project     = "hybrid-toy"
Environment = "dev"
ManagedBy   = "terraform"
```

**파드 리소스 — 계약값**

| 항목 | 값 |
|---|---|
| WAS·BFF `limits.cpu` | **500m** (1코어 아님) |
| Namespace ResourceQuota `limits.cpu` | **6** |
| WAS JVM `-Xmx` | 메모리 limit의 **70~75%** |
| 롤아웃 | `maxUnavailable: 0` |

> 🚨 **개별 파드 limits × 파드 수 ≤ ResourceQuota 를 항상 함께 계산한다.**
> quota가 소진되면 파드가 **아예 생성되지 않아** `describe pod`·`describe rs`·로그·이벤트가 전부 비어 있다. 유일한 단서는 `kubectl -n app describe resourcequota` 한 줄이다.
> 🚨 **LimitRange 하에서 `-Xmx` 를 512Mi 그대로 잡으면 OOMKill 된다.** 힙 외 영역(메타스페이스·스레드 스택·네이티브)을 남겨야 한다.

---

### 6.5 애플리케이션 인증 계약

**책임 분리 — 이 표가 유일한 기준이다.**

| 주체 | 담당 | 금지 |
|---|---|---|
| **WAS** | DB 조회, BCrypt 검증, 회원가입, 실패 카운트, 30분 잠금 | **JWT 발급 금지. 쿠키 생성 금지** |
| **BFF** | JWT 발급·검증, 쿠키·Bearer 처리, CSRF, 권한 판정 | **DB 직접 접근 금지. 비밀번호 해싱 금지** |
| **patient-web** | `/api/bff/patient/**` 호출 | **직원 API 호출·프록시 금지** |
| **OKD Web** | 서버사이드 프록시, Service Token·직원 JWT 보관 | **브라우저에 토큰 노출 금지** |

**미채택 (백로그):** Cognito, Refresh Token, MFA, JWT 키 회전, 폐기 목록, 직원 최초 비밀번호 강제 변경.

**로그인 흐름**

```
로그인 요청 → BFF → WAS(DB + BCrypt 검증)
            → WAS가 {actor_id, actor_type, role, name} 반환 (토큰 없음)
            → BFF가 Nimbus로 JWT 발급
```

**JWT 규격**

| 항목 | 값 |
|---|---|
| 알고리즘 | HS256 |
| 키 | 32바이트 이상 임의값. Secret `bff-secret` / key `JWT_SIGNING_KEY` |
| claim | `sub`, `actor_type`, `role`, `iss`, `aud`, `iat`, `exp` |
| 역할 표현 | **`role` 단수 문자열.** `roles` 배열 사용 금지 |
| 환자 TTL | **30분** |
| 직원 TTL | **8시간** |
| 금지 claim | 이름, 생년월일, 전화번호, 진단·처방 정보, 비밀번호 |

**전달수단 ↔ actor_type 바인딩 — 서명 검증만으로는 불충분하다**

| 전달수단 | 허용 actor_type | 허용 경로 |
|---|---|---|
| `PATIENT_TOKEN` 쿠키 | `PATIENT` 만 | `/api/bff/patient/**` |
| `Authorization: Bearer` | `STAFF` 만 | `/api/bff/staff/**` |

불일치·누락·미상 actor_type은 전부 **401**. BFF 검증 순서:
`Bearer 확인 → 없으면 쿠키 확인 → 둘 다 없으면 401 → 서명/iss/aud/exp → 전달수단 바인딩 → role→권한 변환`

> 직원 JWT를 환자 쿠키에 실으면 **서명은 통과한다.** 바인딩만이 이를 막는다.

**환자 쿠키 / CSRF**

| 쿠키 | 속성 |
|---|---|
| `PATIENT_TOKEN` | HttpOnly ✅ / Secure ✅ / SameSite=Lax / **Path=`/api/bff/patient`** / Max-Age=1800 |
| `XSRF-TOKEN` | HttpOnly ❌ / Secure ✅ / SameSite=Lax / **Path=`/`** |

> 🚨 **두 쿠키의 Path가 다르다. 의도된 것이다.**
> `XSRF-TOKEN` 은 JS가 읽어야 하는데 `document.cookie` 는 **현재 문서 경로**의 쿠키만 반환한다. 화면은 `/` 에서 열리므로 Path를 축소하면 JS가 토큰을 영원히 읽지 못한다.
> Path 축소는 `PATIENT_TOKEN`(HttpOnly) 에만 적용한다.

- 환자 JWT를 응답 JSON·localStorage에 저장하지 않는다.
- CSRF 적용: `POST` / `PATCH` / `DELETE`. 직원 Bearer 경로는 대상 제외.
- 환자 흐름: `GET /auth/csrf` → 쿠키 수신 → register/login에 `X-XSRF-TOKEN` 헤더 → 성공 시 `PATIENT_TOKEN` 수신.
- **CSRF 토큰은 매 요청 직전 다시 읽는다.** 최초 1회만 읽어 캐시하면 갱신 후 전부 403이 된다(인가 문제로 오진하기 쉽다).

**역할 계약**

`PATIENT` / `DOCTOR` / `NURSE` / `ADMIN_STAFF` — 이 4종만 사용한다. (`RECEPTION`, `BILLING`, `ADMIN` 미사용)

| 역할 | 권한 |
|---|---|
| PATIENT | 본인의 예약·기록·처방전 |
| DOCTOR | 환자 목록 / 차트 조회 / 상병코드 조회 / **차트·처방 작성** |
| NURSE | 환자 목록 / 차트 조회 / 상병코드 조회 / 차트·처방 작성 **불가** |
| ADMIN_STAFF | 관리자 전용 API |

Spring Security 권한명: `ROLE_PATIENT` / `ROLE_DOCTOR` / `ROLE_NURSE` / `ROLE_ADMIN_STAFF`

> 처방 발급은 차트 작성의 일부다. 별도 권한을 만들지 않는다. `NURSE`의 `POST /api/bff/staff/charts` 는 **403**이며, 처방 항목 포함 여부와 무관하다.

**계정 잠금 — 환자·직원 동일**

5회 연속 실패 → `failed_login_count=5`, `locked_until = now + 30분` → 잠금 중 요청 **423** → 30분 후 자동 해제 → 로그인 성공 시 카운트 0, `locked_until=NULL`. 관리자 수동 해제 API는 미구현.

> 🚨 **실패 카운터는 `@Transactional(propagation = REQUIRES_NEW)` 별도 빈으로 분리한다.**
> 인증 실패는 예외로 응답하고 예외는 트랜잭션을 롤백한다. 같은 트랜잭션에서 카운터를 올리면 증가분이 함께 사라지고, **응답은 정상이라 어떤 시나리오도 이를 잡지 못한다.**
> 자기호출은 프록시를 타지 않으므로 반드시 다른 빈이어야 한다.

---

### 6.6 API 경로 계약

**외부 환자 (ALB 경유)**

```
GET   /api/bff/patient/auth/csrf
POST  /api/bff/patient/auth/register
POST  /api/bff/patient/auth/login
POST  /api/bff/patient/auth/logout
GET   /api/bff/patient/doctors
GET   /api/bff/patient/slots
POST  /api/bff/patient/appointments
GET   /api/bff/patient/appointments
PATCH /api/bff/patient/appointments/{id}
GET   /api/bff/patient/records
GET   /api/bff/patient/prescriptions
```

**내부 직원 (Tunnel 경유 — ALB 등록 금지)**

```
POST /api/bff/staff/auth/login
POST /api/bff/staff/auth/logout
GET  /api/bff/staff/patients
GET  /api/bff/staff/patients/{visit_no}/chart
POST /api/bff/staff/charts
GET  /api/bff/staff/icd-codes
/api/bff/staff/admin/**        ← ADMIN_STAFF 전용
```

**경로를 늘리지 않는다.** 경로 추가는 Ingress(§6.9)·BFF Security 정책·Cloudflare Access·게이트 검증을 전부 재실행 대상으로 만든다(§7.12).

| 경로 | 확정 의미 | 권한 |
|---|---|---|
| `GET /api/bff/staff/patients` | **당일 예약 목록**. `?date=YYYY-MM-DD` (미지정 시 오늘), `?status=BOOKED` 선택. 응답에 `visit_no`·`patient_name`·`slot_at`·`status` 포함 | DOCTOR / NURSE |
| `GET /api/bff/staff/patients/{visit_no}/chart` | 해당 예약의 차트 + **처방 1건 + 처방 항목 N건**을 한 번에 반환. 미작성이면 **404 `not_found`** | DOCTOR / NURSE |
| `GET /api/bff/staff/icd-codes` | `?q=` (코드 prefix 또는 명칭 부분일치, **2자 이상 필수**), 상한 **50건** 고정 | DOCTOR / NURSE |
| `POST /api/bff/staff/charts` | 차트 + 처방 + 처방 항목을 **단일 트랜잭션**으로 생성. 부분 저장 없음 | **DOCTOR 전용** |

`POST /api/bff/staff/charts` 요청 본문 (snake_case — §6.7):

```json
{
  "visit_no": "V20260810-0007",
  "icd_code": "E1140",
  "chief_complaint": "다뇨, 하지 저림",
  "note": "혈당 조절 불량. 2주 후 재내원.",
  "prescription_items": [
    { "drug_name": "메트포르민정 500mg", "dosage": "1정", "frequency": "1일 2회", "duration_days": 14 }
  ]
}
```

- `prescription_items` 가 **빈 배열이면 처방 없는 차트**로 저장한다. `null`·필드 누락도 동일하게 처리한다.
- `icd_code` 는 `icd_code` 테이블에 존재해야 한다. 없으면 **400 `validation_error`**.
- 동일 `visit_no` 재요청은 **409 `duplicate_prescription`**.
- `patient_id` 는 **본문에서 받지 않는다.** `visit_no` → `appointment` 조인으로 서버가 결정한다(위조 방어 4번 원칙).

**예약 슬롯 조회 기준**

조회 시작점은 **`max(조회일 00:00, now)`** 다. 날짜 범위로만 자르면 지나간 시각까지 반환되어, 예약 생성 검증(현재 시각 기준)과 어긋나 `400 invalid_date` 가 난다.
> **조회 필터와 생성 검증의 판정 기준을 반드시 일치시킨다.**

**WAS 내부 API (ALB·Cloudflare 노출 금지)**

```
POST /internal/patient/auth/register
POST /internal/patient/auth/login
POST /internal/staff/auth/login
/internal/patient/**
/internal/staff/**
```

**Spring Security 최소 정책 (BFF)**

| 경로 | 정책 |
|---|---|
| `/healthz`, `/readyz`, `/actuator/health/**` | permitAll |
| `GET /api/bff/patient/auth/csrf` | permitAll |
| `POST /api/bff/patient/auth/register` | permitAll + CSRF |
| `POST /api/bff/patient/auth/login` | permitAll + CSRF |
| `POST /api/bff/staff/auth/login` | permitAll (Cloudflare 내부 경로로만 도달) |
| `/api/bff/patient/**` | `PATIENT` |
| `/api/bff/staff/admin/**` | `ADMIN_STAFF` |
| `/api/bff/staff/**` | API별 `DOCTOR` / `NURSE` / `ADMIN_STAFF` |
| 나머지 | **거부** |

**BFF → WAS 신원 헤더 — 위조 방어 규칙**

```
X-Actor-Type : PATIENT | STAFF
X-Actor-Id   : 12
X-Actor-Role : PATIENT | DOCTOR | NURSE | ADMIN_STAFF
X-Trace-Id   : <UUID>
```

1. BFF는 **외부 요청의 `X-Actor-*` 를 먼저 제거한다.**
2. JWT를 검증한다.
3. `sub` / `actor_type` / `role` 로 헤더를 **새로 생성**한다.
4. WAS는 `X-Actor-Id`를 인증된 사용자 ID로 사용한다. **body의 `patient_id`를 신뢰하지 않는다.**
5. WAS는 2차 검증을 수행한다 — 경로와 `actor_type`/`role` 불일치, 필수 헤더 누락은 **403**.
6. 인증 3개 API(`/internal/*/auth/*`)에는 `X-Actor-*` 를 보내지 않는다. `X-Trace-Id` 만 전달한다.

> BFF가 1차 방어선, WAS가 최종 방어선이다. BFF에 버그가 나도 WAS가 막는다.

**BFF → WAS 호출 정책**

| 항목 | 값 |
|---|---|
| HTTP 클라이언트 | **`JdkClientHttpRequestFactory`** |
| connect timeout | 2초 |
| read timeout | 5초 |
| 자동 Retry | **없음** (특히 인증 POST — 중복 가입·잠금 조기 발동) |
| 쿼리 값 전달 | **URI 템플릿 변수로만.** 문자열 연결·사전 인코딩 금지 |
| WAS 400/401/404/409/423 | 계약된 상태·본문 그대로 전달 |
| WAS 500 / 연결 실패 / Timeout | **503 `upstream_unavailable`** 로 변환 |

> 🚨 `SimpleClientHttpRequestFactory`(HttpURLConnection)를 쓰지 않는다. **401만 선택적으로 본문을 삼킨다**(인증 협상으로 오인해 에러 스트림을 소비). 409·400은 정상이라 원인 추적이 매우 어렵다.
> 🚨 쿼리 값을 `UriUtils.encodeQueryParam` 으로 미리 인코딩해 `uri(String)` 에 넘기면 **이중 인코딩**된다(`%` → `%25`). 한글 검색만 0건이 되는 형태로 발현한다.
> 🚨 WAS 콜드스타트가 read timeout 5초를 넘을 수 있다. 타임아웃 계약은 유지하고 **WAS 파드에 `startupProbe`** 를 건다.

---

### 6.7 오류 · trace_id · JSON 네이밍

**공통 오류 형식 — 예외 없음**

```json
{ "error": "slot_taken", "message": "방금 다른 분이 예약했습니다.", "trace_id": "1f993c68-..." }
```

**오류 코드**

| HTTP | code |
|---|---|
| 400 | `validation_error`, `invalid_status`, `invalid_date`, `future_birth_date` |
| 401 | `unauthorized`, `invalid_credentials` |
| 403 | `forbidden` |
| 404 | `not_found` |
| 409 | `duplicate_booking`, `slot_taken`, `patient_exists`, `duplicate_prescription` |
| 423 | `account_locked` |
| 429 | `rate_limited` |
| 500 | `internal_error` |
| 502 | `external_api_error` |
| 503 | `upstream_unavailable` |

> 스택트레이스·SQL·테이블명·내부 호스트명을 응답에 포함하지 않는다.
> 계정 없음과 비밀번호 오류를 **구분하지 않는다** (둘 다 `401 invalid_credentials`).

**trace_id**

- BFF가 요청마다 UUID를 생성한다. **외부가 보낸 `X-Trace-Id`는 신뢰하지 않는다.**
- BFF 로그 / WAS 로그 / 오류 JSON / 응답 헤더 `X-Trace-Id` 에 동일 값이 나타난다.
- **성공 JSON에는 넣지 않는다.**
- `trace_id` 는 **MDC → 응답 헤더 → 신규 생성** 3단으로 확보한다. **절대 null을 내보내지 않는다.**

> 🚨 **`HttpServletResponse.reset()` 을 쓰지 않는다.** 이미 설정된 모든 헤더를 지운다 — `TraceIdFilter` 의 헤더와 Security가 큐에 넣은 `Set-Cookie` 가 함께 사라진다. 상태·본문만 덮어쓴다.
> 🚨 **필터에서 만든 오류 응답은 본문이 빌 수 있다.** 필터는 DispatcherServlet 밖이라 `getWriter()` 커밋 시점이 컨테이너에 좌우된다. 바이트로 만들어 `setContentLength` → `getOutputStream()` → `flushBuffer()`.

**JSON 네이밍**

| 계층 | 규칙 |
|---|---|
| Java 필드 | camelCase |
| HTTP JSON | **snake_case** |
| DB 컬럼 | snake_case |

```yaml
spring:
  jackson:
    property-naming-strategy: SNAKE_CASE
```

개별 `@JsonProperty` 반복 사용은 피한다. 필수 확인: `patientId→patient_id`, `birthDate→birth_date`, `visitNo→visit_no`, `actorType→actor_type`, `traceId→trace_id`.

**nginx 응답 charset** — `charset utf-8; charset_types ...` 를 설정한다. 미설정 시 클라이언트가 임의 해석해 한글이 깨진다(브라우저는 `<meta charset>` 보다 헤더를 먼저 본다).

---
### 6.8 DB 계약

**표기 확정** (DB팀 기존 스키마 ↔ 계약)

| 항목 | 확정 | 판단 |
|---|---|---|
| 환자 PK | **`patient_id`** | DB팀 현행 유지. API는 `actor_id`·`patient.id` 로 매핑 |
| 직원 PK | **`staff_id`** | 동일 |
| 직원 활성 | **`status ENUM('ACTIVE','INACTIVE','SUSPENDED')`** | WAS가 `ACTIVE` 만 로그인 허용 |
| `must_change_password` | **`DEFAULT 0`** | 초안의 `DEFAULT 1` 에서 변경 |
| `staff_user.role` | **`ENUM('DOCTOR','NURSE','ADMIN_STAFF')`** | `PATIENT` 는 `patient_user` 계층에서 부여 |
| 시간대 | **Asia/Seoul, 전 컬럼 `DATETIME`** | JDBC `serverTimezone=Asia/Seoul` |

**계정 테이블 필수 컬럼**

`patient_user`: `patient_id` / `login_id` UNIQUE / `password_hash` / `name` / `birth_date` / `failed_login_count` DEFAULT 0 / `locked_until` NULL / `created_at`

`staff_user`: `staff_id` / `login_id` UNIQUE / `password_hash` / `name` / `role` / `department` / `status` / `must_change_password` DEFAULT 0 / `failed_login_count` DEFAULT 0 / `locked_until` NULL / `created_at`

**규칙**

- 비밀번호는 **BCrypt 해시만** 저장. 평문 컬럼 없음.
- 환자는 API로 가입한다. **직원 셀프 가입 없음** — seed SQL로 생성.
- 테스트 직원 계정은 `must_change_password = 0`.
- 예약 동시성은 **DB UNIQUE 제약**으로 최종 방어한다 (`slot_taken` 판정 근거).
- 앱은 `app_was` 계정만 사용한다. `admin` 은 계정 생성·스키마 변경 전용.

**예약 상태 매핑**

DB 원본값 → **WAS 표준 enum** 변환 매퍼는 1개만 유지한다. 화면별 한글 라벨은 각 Web이 처리한다.

```
DB: booked  →  API: BOOKED  →  환자 화면 "예약" / 직원 화면 "대기"
```

WAS는 DB 원본값도, 한글 라벨도 반환하지 않는다.

---

**진료·처방 테이블**

| 테이블 | 행수 | 역할 |
|---|---|---|
| `icd_code` | **14,283** | KCD 상병코드 마스터. `code` PK |
| `icd_code_synonym` | **37,543** | 검색용 동의어 색인. `code` FK, N:1 |
| `chart` | 진료마다 1 | 예약 1건당 차트 1건 |
| `prescription` | 차트마다 0~1 | 차트 1건당 처방 최대 1건 |
| `prescription_item` | 처방마다 1~N | 약품 항목 |

**`icd_code`** — `code` VARCHAR(6) PK / `name_kr` VARCHAR(200) NOT NULL / `name_en` VARCHAR(255) NULL / `gender_restriction` CHAR(1) NULL / `age_min` **INT** NULL / `age_max` **INT** NULL / `infectious_class` VARCHAR(8) NULL / `oriental_medicine` VARCHAR(16) NULL

**`icd_code_synonym`** — `synonym_id` BIGINT PK AUTO_INCREMENT / `code` VARCHAR(6) NOT NULL FK→`icd_code.code` / `name_kr` VARCHAR(200) NOT NULL / `name_en` VARCHAR(255) NULL

> ⚠️ **`code`는 원본에서 유일하지 않다.** `E1140` 한 코드에 명칭 레코드가 **60건** 존재한다. 마스터 1행 + 동의어 N행으로 분리하지 않으면 PK 제약 위반으로 적재가 실패한다.

**필수 인덱스** — 없으면 37,543행 풀스캔이 매 타건마다 발생한다

```sql
INDEX idx_icd_syn_code   ON icd_code_synonym (code)
INDEX idx_icd_syn_name   ON icd_code_synonym (name_kr(32))
INDEX idx_icd_code_name  ON icd_code (name_kr(32))
```

**`chart`** — `chart_id` BIGINT PK / `visit_no` VARCHAR(32) **UNIQUE** FK→`appointment.visit_no` / `patient_id` BIGINT NOT NULL / `doctor_staff_id` BIGINT NOT NULL FK→`staff_user.staff_id` / `icd_code` VARCHAR(6) NOT NULL FK→`icd_code.code` / `icd_name_snapshot` VARCHAR(200) NOT NULL / `chief_complaint` VARCHAR(500) NULL / `note` TEXT NULL / `created_at` DATETIME NOT NULL

**`prescription`** — `prescription_id` BIGINT PK / `chart_id` BIGINT **UNIQUE** FK→`chart.chart_id` / `patient_id` BIGINT NOT NULL / `issued_by_staff_id` BIGINT NOT NULL / `issued_at` DATETIME NOT NULL

**`prescription_item`** — `item_id` BIGINT PK / `prescription_id` BIGINT NOT NULL FK / `drug_name` VARCHAR(200) NOT NULL / `dosage` VARCHAR(50) NOT NULL / `frequency` VARCHAR(50) NOT NULL / `duration_days` **INT** NOT NULL / `line_no` **INT** NOT NULL

**숫자 컬럼은 `INT` 로 통일한다. `TINYINT`/`SMALLINT` 를 쓰지 않는다.**

Hibernate 는 Java 타입에서 JDBC 타입 코드를 정하고 `ddl-auto: validate` 가 이를 실제 컬럼과 대조한다.

| Java | JDBC | MySQL |
|---|---|---|
| `int` / `Integer` | INTEGER | `INT` |
| `short` / `Short` | SMALLINT | `SMALLINT` |
| `byte` / `Byte` | TINYINT | `TINYINT` |

카운터·일수·연령을 `TINYINT`/`SMALLINT` 로 두면 엔티티를 `byte`/`short` 로 낮춰야 하고, `UNSIGNED`(0~255)가 Java `byte`(-128~127)를 넘어 **조용한 오버플로**가 생긴다. 저장 공간 차이는 이 규모에서 무의미하다.

적용 컬럼: `patient_user.failed_login_count` · `staff_user.failed_login_count` · `icd_code.age_min` · `icd_code.age_max` · `prescription_item.duration_days` · `prescription_item.line_no`

**`chart.note` 매핑** — `@Lob` + **`length = 65535`**.
`@Lob` 만 붙이면 MySQL 방언이 CLOB 실제 타입을 **컬럼 길이로** 고른다(~255 tinytext / ~65535 text / ~16M mediumtext). 기본값 255가 적용되어 DDL의 `TEXT` 와 불일치한다.

**규칙**

- `chart.visit_no` **UNIQUE**가 처방 중복 발급의 최종 방어선이다(`duplicate_prescription` 판정 근거). **애플리케이션 체크는 보조, DB 제약이 본선.**
- `chart.icd_name_snapshot` — 상병코드 명칭은 KCD 개정 시 바뀐다. **발급 시점 명칭을 복사 보관한다.** 과거 처방전이 소급 변경되면 의료 기록으로서 무효다.
- `prescription.patient_id` 는 `chart` 에서 파생한다. 요청 본문 값을 신뢰하지 않는다.
- `icd_code` / `icd_code_synonym` 은 **참조 마스터**다. WAS는 `SELECT` 만 수행한다(§9.2 GRANT로 강제).
- 처방 항목 약품명은 **자유 텍스트**다. 의약품 표준코드 연동은 백로그.

---

### 6.9 외부 ALB Ingress 경로 계약

```
/api/bff/patient  →  bff-svc:8080
/                 →  patient-web-svc:8080     ← 반드시 마지막
```

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
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '15'
    alb.ingress.kubernetes.io/success-codes: '200'
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          # 환자 API — 반드시 먼저 선언
          - path: /api/bff/patient
            pathType: Prefix
            backend:
              service:
                name: bff-svc
                port: { number: 8080 }

          # 기본 경로 — 반드시 마지막
          - path: /
            pathType: Prefix
            backend:
              service:
                name: patient-web-svc
                port: { number: 8080 }
```

**금지 규칙**

| 금지 | 이유 |
|---|---|
| `/api` → bff-svc | 범위가 과하다 |
| `/api/bff/staff` → bff-svc | 직원 API의 외부 노출 |
| `/` 를 먼저 선언 | Prefix 매칭이 `/`에서 전부 흡수된다 — **환자 흐름이 물리적으로 성립 불가** |

- `patient-web`은 `/api/bff/staff/**`를 프록시하지 않고 **404**를 반환한다.
- 환자 Web과 API가 동일 도메인이므로 **CORS 구성을 추가하지 않는다.**
- ACM ARN 적용 직후 반드시 대조한다:
  ```powershell
  kubectl -n app get ingress patient-web -o jsonpath="{.metadata.annotations}"
  ```

---

### 6.10 공공데이터(KCD 상병코드) 적재 계약

**적재 방식: 오프라인 1회 seed. 런타임 외부 호출 없음.** (판단 근거 §7.11)

```
[사람 1회]  공공데이터포털 다운로드  →  db/raw/data.json  (git 커밋)
[사람 1회]  db/tools/convert-icd.ps1  →  db/04_icd_seed.sql  (git 커밋)
[DB팀 1회]  04_icd_seed.sql 실행      →  icd_code + icd_code_synonym
[런타임]    WAS: SELECT only          →  외부 아웃바운드 0건
```

**원본 데이터 실측** (`db/raw/data.json`, 19MB)

| 항목 | 값 |
|---|---|
| 전체 행수 | **47,798** |
| 원본 키 | `상병기호` `한글명` `영문명` `완전코드구분` `주상병사용구분` `성별구분` `상한연령` `하한연령` `법정감염병구분` `양한방구분` |
| 최대 길이 | `상병기호` 6 / `한글명` 170 / `영문명` 223 |

**적재 필터**

```
완전코드구분 <> 'N'  AND  주상병사용구분 <> 'N'
```

| 구분 | 행수 |
|---|---|
| 원본 | 47,798 |
| 제외 (미완전코드 또는 주상병 사용불가) | **10,255** |
| **`icd_code_synonym` 적재** | **37,543** |
| **`icd_code` 적재** (고유 상병기호) | **14,283** |

> ⚠️ **판정 값이 반전되어 있다.** 이 데이터셋에서 `'N'` 은 "완전코드 **아님**" / "주상병 사용 **불가**" 를 뜻한다. 빈 문자열이 정상(사용 가능)이다. `= 'Y'` 로 필터하면 **0건이 적재된다.**

**대표명 선정** — 동일 `상병기호`의 첫 등장 레코드를 `icd_code.name_kr`/`name_en` 으로 삼는다(원본이 KCD 공표 순서 유지). 나머지 전 행(대표명 포함)은 `icd_code_synonym` 에 적재한다 — 검색은 동의어 테이블만 조회하면 되므로 UNION이 불필요해진다.

**컬럼 매핑**

| 원본 | 대상 | 변환 |
|---|---|---|
| `상병기호` | `code` | 그대로 |
| `한글명` | `name_kr` | 그대로 |
| `영문명` | `name_en` | 빈 문자열 → `NULL` |
| `성별구분` | `gender_restriction` | 빈 문자열 → `NULL` |
| `상한연령` / `하한연령` | `age_max` / `age_min` | 빈 문자열 → `NULL`, 그 외 정수 |
| `법정감염병구분` | `infectious_class` | 빈 문자열 → `NULL` (보유 코드 486종) |
| `양한방구분` | `oriental_medicine` | 그대로 (한방 전용 151종) |
| `완전코드구분` / `주상병사용구분` | — | **적재하지 않는다.** 필터에만 사용 |

**SQL 생성 규칙 (`convert-icd.ps1`)**

- 출력 인코딩 **UTF-8 (BOM 없음)**. BOM이 붙으면 MySQL 클라이언트가 첫 구문을 깨뜨린다.
- `INSERT ... VALUES` **1,000행 배치**. 단건 INSERT 37,543회는 수 분이 걸린다.
- 파일 선두에 `SET NAMES utf8mb4;` / `SET autocommit=0;`, 말미에 `COMMIT;`
- 작은따옴표는 `''` 로 이스케이프한다(실측 5건). 백슬래시는 0건이나 방어적으로 처리한다.

**재적재 방식 — `DELETE FROM icd_code` 를 쓰지 않는다**

`chart.icd_code` 가 `ON DELETE RESTRICT` 로 마스터를 참조한다. 차트가 생기는 순간 `ERROR 1451` 로 실패한다.

| 테이블 | 방식 | 이유 |
|---|---|---|
| `icd_code_synonym` | `TRUNCATE` 후 전량 재적재 | 참조하는 테이블이 없다 |
| `icd_code` | **UPSERT** (`INSERT ... AS new ON DUPLICATE KEY UPDATE`) | 진료 기록을 보존하면서 명칭만 갱신 |

- **`AS new` 별칭 형식**을 쓴다. 구형 `VALUES(col)` 은 MySQL 8.0.20+ 에서 deprecated. **최소 요구 버전: MySQL 8.0.19**
- 실측: 차트가 `E1140` 참조 중인 상태에서 재적재 → 마스터 명칭은 갱신되고 `chart.icd_name_snapshot` 은 **발급 시점 값 유지**. §6.8 스냅샷 설계가 의도대로 동작한다.

**`ANALYZE TABLE` 을 반드시 실행한다**

| 시점 | `icd_code` 추정 | `icd_code_synonym` 추정 |
|---|---|---|
| 적재 직후 | **3** | **2** |
| `ANALYZE TABLE` 후 | 14,433 | 37,883 (근사치. 정상) |

추정치가 3행이면 옵티마이저가 인덱스를 버리고 풀스캔을 고른다. seed 파일 말미에 `ANALYZE TABLE icd_code, icd_code_synonym;` 을 포함한다.

**검증**

```sql
SELECT COUNT(*) FROM icd_code;           -- 14283
SELECT COUNT(*) FROM icd_code_synonym;   -- 37543
SELECT code, name_kr FROM icd_code WHERE code = 'E1140';
SELECT COUNT(*) FROM icd_code_synonym WHERE code = 'E1140';  -- 60
```

**검색 성능 실측** (MySQL 8.0.46 / 37,543행 / `ANALYZE` 후 / 상한 50건)

| 검색 패턴 | 실행 계획 | 스캔 행수 | 응답 |
|---|---|---|---|
| `code LIKE 'E11%'` (코드 prefix) | `range` — `idx_icd_syn_code` | 630 | **1.3ms** |
| `name_kr LIKE '당뇨%'` (명칭 prefix) | `range` — `idx_icd_syn_name` | 255 | — |
| `name_kr LIKE '%당뇨%'` (부분일치) | `ALL` — 풀스캔 | 39,675 | **6.6ms** |

부분일치는 인덱스를 타지 않지만 **이 규모에서는 10ms 미만**이다. FULLTEXT는 불필요하다. 데이터가 수십만 건으로 늘거나 동시 사용자가 증가하면 그때 전환한다.

**갱신 정책** — KCD는 연 1~2회 개정된다. 개정 시 `data.json` 교체 → 스크립트 재실행 → `04_icd_seed.sql` 재커밋 → 재적재. 기존 `chart.icd_name_snapshot` 은 갱신하지 않는다.

---

## §7. 설계상 핵심 판단

> **각 판단에는 대가가 있다.** 대가를 명시하지 않은 결정은 결정이 아니다.

### 7.1 ALB를 Terraform으로 만들지 않는다
LBC가 Ingress를 감지해 ALB를 동적 생성하는 것이 EKS 표준이다. Terraform으로 만들면 Target Group을 수동 관리해야 하고 파드 IP 변경마다 드리프트가 난다.
**Terraform 범위:** IRSA 권한 + ACM 인증서. **EKS팀 범위:** Ingress 작성 → ALB 생성.

### 7.2 ECR을 `-target`으로 선행 apply 한다
ECR은 의존성이 없다. 먼저 만들면 EKS팀이 클러스터 생성을 기다리지 않고 빌드·푸시를 시작한다. `-target`은 평시 안티패턴이나 **팀 언블로킹 용도는 정당하다.** 직후 전체 apply로 정합화한다.

### 7.3 `create_database_subnet_group = false`
`modules/rds` 에 이미 `aws_db_subnet_group` 이 있다. 둘 다 켜면 중복 리소스가 생긴다. **DB 리소스는 DB팀 디렉토리에 모은다.**
> ⚠️ `create_database_subnet_route_table` 은 **`true`** 다. 두 인자는 역할이 다르다.

### 7.4 `single_nat_gateway = true`
NAT는 시간당 + 데이터 처리 과금이다. **대가:** AZ 장애 시 해당 NAT를 쓰는 파드 전체의 아웃바운드가 끊긴다(SPOF).

### 7.5 `image_tag_mutability = "IMMUTABLE"`
동일 태그 재푸시를 차단한다. **대가:** `:latest` 푸시 실패. git SHA 태그를 강제한다. 이 제약이 이미지 ↔ 커밋 추적의 유일한 근거다.

### 7.6 EKS 엔드포인트 public + private 병행
팀원이 각자 PC에서 `kubectl`을 써야 한다. **대가:** API 서버가 인터넷에 노출된다. IAM 인증이 걸려 있으나 운영 전환 시 private 전용 + CIDR 제한 필수.

### 7.7 `skip_final_snapshot = true`
destroy가 스냅샷 대기로 막히는 것을 방지한다. **대가:** 데이터 완전 소실. **DB팀은 DDL·seed를 반드시 git에 커밋한다.** 복구 경로는 이것뿐이다.

### 7.8 cloudflared를 BFF 담당이 맡는다
cloudflared는 `bff-svc`를 직접 호출한다. 호출 대상을 아는 사람이 배포하는 것이 경계상 자연스럽다.

### 7.9 BFF `/readyz`를 WAS에 종속시키지 않는다
BFF의 준비 상태를 WAS 상태로 판정하면 WAS 일시 장애가 BFF Pod 전량 NotReady → ALB Target 전량 제거 → **부분 장애가 전면 장애로 승격**된다. WAS 장애는 `503 upstream_unavailable` 응답으로 표현한다.

### 7.10 Cloudflare Access JWT를 BFF가 검사하지 않는다
`Cf-Access-Jwt-Assertion` 헤더의 **존재 여부만** 확인하는 것은 보안이 아니다(위조 가능). Access JWT 검증은 대시보드의 **Protect with Access** 설정으로 cloudflared가 수행한다. BFF는 **직원 애플리케이션 JWT와 role**을 검증한다.

### 7.11 WAS가 런타임에 공공데이터포털을 호출하지 않는다

"WAS가 공공데이터포털에서 API를 받아와 DB에 저장한다"는 요구를 **런타임 호출로 구현하지 않는다.** 오프라인 seed로 대체한다(§6.10).

| 런타임 호출 시 발생하는 문제 | 근거 |
|---|---|
| 아웃바운드가 **단일 NAT** 를 경유한다 | §7.4 — AZ 장애 시 진료 코드 조회 전체 중단. 인프라 SPOF가 **진료 기능 SPOF로 승격**된다 |
| WAS `/readyz` 의 의미가 흐려진다 | §6.1 — 외부 API를 얹으면 §7.9와 같은 종속 전파가 재발한다 |
| 시크릿이 6종 → 7종으로 늘어난다 | 서비스키 발급·전달·회전이 전부 사람 작업이다 |
| 대상 데이터가 **정적 마스터**다 | KCD는 연 1~2회 개정. 47,798행을 요청마다 프록시할 근거가 없다 |
| 외부 API 응답시간이 BFF 5초 read timeout 안에 들어온다는 보장이 없다 | 초과 시 `503`. 장애 원인이 외부로 이동해 진단이 어려워진다 |

**시연 요건으로 실시간 수집을 보여야 한다면**, WAS가 아니라 **일회성 Kubernetes Job(`icd-loader`)** 으로 분리한다. Job은 1회 실행 후 종료하며 WAS는 그 존재를 알지 못한다. Job 실패가 WAS 기동·헬스체크에 영향을 주지 않는 것이 유일한 허용 조건이다.

### 7.12 처방 발급에 신규 API 경로를 만들지 않는다

`POST /api/bff/staff/prescriptions` 를 신설하면 다음이 전부 재검증 대상이 된다 — BFF Security 정책(§6.6), 역할별 권한 매핑, Cloudflare Access 경유 동작, G3 체크리스트. 얻는 것은 URL의 의미적 선명함뿐이다.

**차트와 처방은 같은 진료 행위의 두 면이다.** 차트 없는 처방은 의료 기록으로 성립하지 않으므로 두 리소스의 생명주기는 애초에 분리되지 않는다. `POST /api/bff/staff/charts` 단일 트랜잭션이 도메인적으로도 옳다.

**대가:** 처방만 수정하는 API가 없다. 수정·취소가 필요해지면 그때 경로를 추가한다 — 뼈대 완성 후다(§0.3).

### 7.13 관측성을 관리형 애드온으로 도입한다

Prometheus + Grafana 자체 운영 대신 **Amazon CloudWatch Observability EKS 애드온**을 채택한다.

| 근거 | 설명 |
|---|---|
| 운영 대상이 늘지 않는다 | 자체 Prometheus는 스토리지·보존·가용성을 우리가 책임져야 한다 |
| 인증 체계가 늘지 않는다 | Pod Identity로 끝난다. Grafana는 별도 인증 체계가 하나 더 생긴다 |
| 대시보드 설계가 불필요하다 | Container Insights가 노드/파드/네임스페이스 뷰를 자동 생성한다 |
| 애드온 라이프사이클 | 업그레이드가 EKS 애드온 관리에 포함된다 |

**대가:** PromQL을 쓸 수 없고(클래식 파이프라인 기준), 벤더 종속이 생기며, 로그·메트릭이 과금 대상이 된다. 보존기간을 명시적으로 낮춰 통제한다(§10.3).

### 7.14 Application Signals(APM)를 켜지 않는다

애드온은 Application Signals를 **기본 ON** 으로 설치한다. 이를 명시적으로 끈다.

뮤테이팅 웹훅이 Service에 매핑된 Deployment에 자동 계측(initContainer·에이전트)을 주입한다. `restartPods` 기본값이 `false` 라 즉시 재시작되지는 않으나, **다음 배포 때 조용히 파드 스펙이 바뀐다.** G3까지 검증을 통과한 워크로드의 재현성이 깨진다.

**대가:** 분산 트레이싱·서비스 맵의 호출관계 그래프가 없다. 요청 단위 추적은 `X-Trace-Id`(§6.7) + CloudWatch Logs Insights로 대체한다 — 이 프로젝트는 애초에 `trace_id` 연속성을 계약으로 갖고 있어 손실이 크지 않다.

---
## §8. 보안 및 암호화 기준

### 8.1 저장 암호화 (at-rest)

`storage_encrypted = true`, AWS 관리형 키(`aws/rds`). 스냅샷·백업·Read Replica가 암호화를 상속한다.

**CMK 전환 — 미적용 (백로그).** 토이 규모에는 오버스펙이며, KMS 키 삭제 대기가 최소 7일이라 destroy 후 재생성 시 alias 충돌이 발생한다.

> ⏱️ `storage_encrypted` 와 `kms_key_id` 는 **기존 인스턴스에서 변경 불가**하다. 스냅샷 → 암호화 복사 → 복원 경로를 타야 한다.

### 8.2 전송 암호화 (in-transit / TLS)

```hcl
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.project_name}-rds-"
  family      = "mysql8.0"

  parameter {
    name  = "require_secure_transport"
    value = "1"        # AWS가 ON을 1로 정규화한다. 상시 drift 제거
  }

  lifecycle { create_before_destroy = true }
  tags = var.common_tags
}
```

**WAS JDBC URL**

```
jdbc:mysql://<endpoint>:3306/commondb?sslMode=REQUIRED&serverTimezone=Asia/Seoul&characterEncoding=UTF-8
```

| 항목 | 판정 |
|---|---|
| `useSSL=true&requireSSL=true` | ❌ **사용 금지.** Connector/J 8.0.13+ 에서 deprecated. 조합에 따라 무시되거나 경고만 남는다 |
| `sslMode=REQUIRED` | ✅ **채택.** 암호화는 강제하되 서버 인증서 체인은 검증하지 않는다 |
| `sslMode=VERIFY_CA` | 백로그. RDS CA 번들을 이미지에 넣고 `trustCertificateKeyStoreUrl` 지정 필요 |
| `sslMode=DISABLED` | ❌ 금지. 로컬 compose도 동일 |

> ⚠️ TLS 옵션 누락 시 커넥션 **100% 실패**한다. `app_was` 는 `REQUIRE SSL` 계정이므로 비TLS 접속은 비밀번호가 정확해도 `Access denied` 다.

### 8.3 마스터 비밀번호 — Secrets Manager

```hcl
# password = var.db_password        <- 제거됨 (배타적 인자)
manage_master_user_password = true
```

> `password` 와 `manage_master_user_password` 는 **동시 지정 불가**하다.

### 8.4 EKS 접근 권한 모델

`enable_cluster_creator_admin_permissions = true` 는 apply 실행자 1명만 관리자로 등록한다. 나머지 팀원은 `kubectl` 자체가 동작하지 않는다.

```hcl
# modules/eks/main.tf — module "eks" 블록 안
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

```hcl
# envs/dev/main.tf
developer_iam_arns = {
  web = "arn:aws:iam::597106152264:user/kusweb"
  bff = "arn:aws:iam::597106152264:user/kusbff"
  was = "arn:aws:iam::597106152264:user/kuswas"
  db  = "arn:aws:iam::597106152264:user/kusdb"
}
```

> `principal_arn` 에 **IAM Group ARN은 쓸 수 없다.** 개별 User ARN 필수.
> IAM 정책과 `access_entries` 는 **별개다.** 전자는 AWS API 호출 권한(`update-kubeconfig`), 후자는 클러스터 내 RBAC. **둘 다 있어야 동작한다.**

**IAM 권한 현황**

| User | `eks:DescribeCluster` (인라인) | `AmazonEC2ContainerRegistryPowerUser` | Secrets Manager |
|---|---|---|---|
| kusweb | ✅ | ✅ | — |
| kusbff | ✅ | ✅ | — |
| kuswas | ✅ | ✅ | — |
| kusdb | ✅ | — | ✅ (인라인) |

> `eks:DescribeCluster` 만 부여하는 AWS 관리형 정책은 없다 — 인라인으로 작성한다.
> 인라인 정책은 `list-attached-user-policies` 에 **나오지 않는다.** `list-user-policies` 로 확인한다.

### 8.5 적용된 보안 통제

| 항목 | 상태 |
|---|---|
| RDS `publicly_accessible = false` | ✅ |
| RDS SG — EKS 노드 SG 출처만 허용 | ✅ |
| DB 서브넷 전용 RT, NAT 라우트 없음 | ✅ |
| DB 서브넷에 `kubernetes.io/*` 태그 없음 | ✅ |
| ECR `scan_on_push = true` / `IMMUTABLE` | ✅ |
| S3 state — 암호화 + 버전관리 + 퍼블릭 차단 + `prevent_destroy` | ✅ |
| 비밀번호 BCrypt 해시만 저장 | ✅ (§6.8) |
| JWT HS256 + Secret 주입 | ✅ (§6.5) |
| 컨테이너 non-root | ✅ (§6.1) |
| CloudWatch Agent — Pod Identity 최소 권한 | ✅ (§10) |

### 8.6 SG description 제약 — ASCII만

| 필드 | 한글 |
|---|---|
| `aws_security_group` 의 `description` / `ingress.description` / `egress.description` | ❌ **불가** (apply 중단) |
| `tags` 값 | ✅ |
| ECR lifecycle policy `description` | ✅ |
| Terraform `variable` / `output` 의 `description` | ✅ (AWS에 전송되지 않음) |

```powershell
Select-String -Path ..\..\modules\*\*.tf -Pattern "description" | Select-String "[가-힣]"
```

### 8.7 IMDS hop limit을 올리지 않는다

EKS 모듈 기본값 `http_put_response_hop_limit = 1` 은 파드 레벨 메타데이터 접근을 막는다. LBC가 `region`/`vpcId` 를 런타임 자동탐색하려다 CrashLoop이 나는 원인이다.

**hop limit 상향은 파드가 노드 IAM을 탈취할 경로를 여는 방향이므로 채택하지 않는다.** 대신 값을 **명시 주입**한다.

```powershell
$lbcRoleArn = terraform output -raw lbc_irsa_role_arn
$vpcId      = aws eks describe-cluster --name hybrid-toy-eks --region ap-northeast-2 --query "cluster.resourcesVpcConfig.vpcId" --output text
$annotation = "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$lbcRoleArn"

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --version 3.5.0 --set clusterName=hybrid-toy-eks --set region=ap-northeast-2 --set vpcId=$vpcId --set serviceAccount.create=true --set serviceAccount.name=aws-load-balancer-controller --set-string $annotation
```

> 📌 **`1/1 Running` 은 leader lease 획득까지만 증명한다.** AWS API 호출 성공은 첫 Ingress 생성 때 드러난다.
> 📌 로그가 `Attempting to acquire leader lease...` 에서 멈춘 것처럼 보이는 건 **정상**이다. standby도 webhook을 서빙하므로 Readiness를 통과한다.
> 📌 **Helm `deployed` 상태는 annotation 값의 정확성을 증명하지 않는다.** 설치 직후 `helm get values` 로 대조한다.

---

## §9. 데이터베이스 운영 계약

### 9.1 접속 경로 — 로컬 PC 직접 접속 불가

| 방식 | 평가 |
|---|---|
| **클러스터 내 임시 파드** | ✅ **권장.** 추가 인프라 0, 보안 설계 유지 |
| Bastion EC2 | 리소스·SG 추가. 오버킬 |
| SG에 내 IP 임시 허용 | ❌ **금지.** 격리 설계 무력화 |

```bash
kubectl -n app run mysql-cli --rm -it --image=mysql:8.0 --restart=Never -- \
  mysql -h <RDS_ENDPOINT> -u admin -p
```

파드 트래픽이 EKS 노드 SG를 경유하므로 RDS SG를 통과한다.

**마스터 비밀번호 조회** (Secrets Manager 관리 — tfvars에 없다)

```powershell
aws secretsmanager get-secret-value --secret-id "<rds_master_secret_arn>" --query SecretString --output text
```

### 9.2 앱 전용 계정 — `admin` 공유 금지

> ⚠️ **DB 단위 GRANT 후 테이블 단위 REVOKE는 MySQL에서 동작하지 않는다.**
> ```
> ERROR 1147 (42000): There is no such grant defined for user 'app_was' on host '%' on table 'icd_code'
> ```
> `partial_revokes=ON` 을 켜도 동일하다(이 변수는 전역→DB 범위 전용). **테이블 단위 명시 부여**로 확정한다. 화이트리스트가 되므로 보안상으로도 낫다.

```sql
CREATE USER IF NOT EXISTS 'app_was'@'%' IDENTIFIED BY '<강력한 비밀번호>';
ALTER  USER 'app_was'@'%' REQUIRE SSL;   -- §8.2 TLS 강제와 정합. 필수

-- 업무 테이블 — 읽기·쓰기
GRANT SELECT, INSERT, UPDATE, DELETE ON commondb.patient_user      TO 'app_was'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON commondb.appointment       TO 'app_was'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON commondb.chart             TO 'app_was'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON commondb.prescription      TO 'app_was'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON commondb.prescription_item TO 'app_was'@'%';

-- 직원 계정 — 읽기 + 잠금 카운터 갱신만 (seed 로만 생성. INSERT/DELETE 불가)
GRANT SELECT, UPDATE         ON commondb.staff_user  TO 'app_was'@'%';

-- 진료 자원 마스터 — DELETE 불가
GRANT SELECT, INSERT, UPDATE ON commondb.doctor      TO 'app_was'@'%';
GRANT SELECT, INSERT, UPDATE ON commondb.doctor_slot TO 'app_was'@'%';

-- 상병코드 마스터 — 읽기 전용
GRANT SELECT ON commondb.icd_code         TO 'app_was'@'%';
GRANT SELECT ON commondb.icd_code_synonym TO 'app_was'@'%';

FLUSH PRIVILEGES;
```

- `DROP` / `ALTER` / `CREATE` 권한은 주지 않는다. 스키마 변경은 DB팀 전담.
- ICD 마스터를 읽기 전용으로 두는 것이 §7.11 "런타임 적재 금지"의 **권한 차원 강제**다. 코드 리뷰에만 의존하지 않는다.
- ⚠️ **테이블을 새로 추가하면 이 목록에 GRANT를 반드시 추가한다.** 누락 시 `SELECT command denied to user 'app_was'`. 이것이 명시 부여 방식의 유일한 대가다.

**검증**

```sql
SHOW GRANTS FOR 'app_was'@'%';
-- USAGE 줄에 REQUIRE SSL / icd_* 는 SELECT 만 / commondb.* 광역 줄 없음
```

> ⚠️ `GRANT ... ON commondb.*` 줄이 남아 있으면 이전 실행의 잔재다.
> `REVOKE ALL PRIVILEGES ON commondb.* FROM 'app_was'@'%';` 로 회수한 뒤 위를 다시 실행한다.

### 9.3 DB 롤백

`skip_final_snapshot = true` 이므로 **RDS destroy = 데이터 완전 소실**이다. 복구 경로는 git의 DDL·seed 재실행뿐이다. 그래서 `db/` 커밋이 필수 단계다(§7.7).

---

## §10. 관측성(Observability)

> 도입 판단은 §7.13(관리형 채택) · §7.14(Application Signals 비활성)를 본다.

### 10.1 구성

| 항목 | 값 |
|---|---|
| 방식 | Amazon CloudWatch Observability **EKS 애드온** |
| 애드온 버전 | `v6.5.0-eksbuild.1` |
| 네임스페이스 | `amazon-cloudwatch` |
| 인증 | **EKS Pod Identity** (IRSA 아님) |
| IAM Role | `hybrid-toy-eks-cwagent-role` + `CloudWatchAgentServerPolicy` |
| 배치 | `cloudwatch-agent`(DaemonSet) · `fluent-bit`(DaemonSet) · `controller-manager`(Deployment) |

**Pod Identity를 택한 이유** — `eks-pod-identity-agent` 가 이미 설치돼 있고(§1.4), IRSA 대비 자격증명 자동 회전·감사성이 우수하며 OIDC 공급자 설정이 불필요하다.

**IAM 신뢰 정책**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "pods.eks.amazonaws.com" },
      "Action": ["sts:AssumeRole", "sts:TagSession"]
    }
  ]
}
```

**애드온 구성값** (`monitoring/cw-addon-config.json`)

```json
{
  "agent": {
    "config": {
      "logs": {
        "metrics_collected": {
          "kubernetes": {
            "enhanced_container_insights": true,
            "accelerated_compute_metrics": false
          }
        }
      }
    }
  },
  "manager": {
    "applicationSignals": {
      "autoMonitor": {
        "monitorAllServices": false
      }
    }
  }
}
```

> 🚨 **`agent.config` 를 지정하면 기본 구성 전체를 덮어쓴다.** 위 JSON에 `application_signals` 키가 없는 것이 곧 에이전트 파이프라인에서의 비활성화다. 실수로 `logs` 블록을 빼먹으면 **Container Insights 자체가 꺼진다.**
> 🚨 **구성 파일은 BOM 없이 저장한다.** AWS CLI는 BOM 붙은 JSON을 파싱하지 못한다(§12.1).

### 10.2 수집 범위

| 대상 | 수집 여부 | 비고 |
|---|---|---|
| 클러스터/노드/파드/네임스페이스 메트릭 | ✅ | Container Insights enhanced |
| 컨트롤러(Deployment/DaemonSet) Desired vs Running | ✅ | 롤아웃 상태 |
| 컨테이너 stdout/stderr | ✅ | `/aws/containerinsights/hybrid-toy-eks/application` |
| EMF 메트릭 원본 | ✅ | `.../performance` |
| dataplane (kubelet·kube-proxy·CNI) | ❌ | **AL2023 노드** — systemd 로깅 방식 변경으로 기본 비수집 |
| host (dmesg·messages·secure) | ❌ | 동일 |
| EKS 컨트롤플레인 로그 (API 서버·감사) | ❌ | 애드온 범위 밖. `update-cluster-config --logging` 별도 |
| 분산 트레이싱 / 서비스 호출 그래프 | ❌ | Application Signals 비활성 (§7.14) |
| `kubectl top` (실시간 사용량) | ❌ | **metrics-server 미설치** — 애드온과 별개 컴포넌트 |
| RDS · ALB 메트릭 | ✅ | 각 서비스가 CloudWatch에 자동 전송. Container Insights와 무관 |

### 10.3 로그 보존 정책

Fluent Bit은 로그 그룹을 **보존기간 무제한**으로 자동 생성한다. **7일로 하향한다.**

```powershell
$groups = aws logs describe-log-groups `
  --log-group-name-prefix "/aws/containerinsights/hybrid-toy-eks" `
  --region ap-northeast-2 --query "logGroups[].logGroupName" --output text

foreach ($g in ($groups -split "\s+" | Where-Object { $_ })) {
  aws logs put-retention-policy --log-group-name $g --retention-in-days 7 --region ap-northeast-2
}
```

> 🚨 **이 시점부터 애플리케이션 로그는 외부에 영속 저장된다.** §4.3 "비밀번호·토큰 로그 출력 금지" 위반이 있었다면 여기서 실체화된다. 도입 직후 반드시 감사한다.

### 10.4 조회 방법 — 두 경로를 구분한다

`kubectl` 은 **지금 살아있는 상태**만 보여준다. 파드가 재시작·삭제되면 사라진다. CloudWatch Logs는 그 이후에도 남는다 — 관측성 도입의 핵심 가치가 여기다.

**즉시 대응 (실시간)**

```powershell
kubectl get events -n app --sort-by=.lastTimestamp   # 원인의 대부분이 여기 요약된다
kubectl describe pod <pod> -n app
kubectl logs <pod> -n app --tail=100
kubectl logs <pod> -n app --previous                 # 죽기 직전 로그
```

**사후 조사 (파드 소멸 후)**

```powershell
aws logs tail /aws/containerinsights/hybrid-toy-eks/application --follow --region ap-northeast-2
```

Logs Insights — 오류 검색:
```
fields @timestamp, kubernetes.pod_name, log
| filter kubernetes.namespace_name = "app"
| filter log like /ERROR|Exception|OOMKilled/
| sort @timestamp desc
| limit 50
```

Logs Insights — 메모리 압박 사전 탐지 (§6.4 `-Xmx` 계약 위반 감지):
```
fields @timestamp, PodName, MEM_UTILIZATION_OVER_POD_LIMIT
| filter Namespace = "app"
| filter MEM_UTILIZATION_OVER_POD_LIMIT > 90
| sort @timestamp desc
```

**대시보드** — CloudWatch 콘솔 → Insights → Container Insights → `hybrid-toy-eks`.

### 10.5 Terraform state 밖의 리소스

애드온을 CLI로 설치했으므로 **`terraform destroy` 가 지우지 않는다.** 종료 시 수동 정리 대상이다.

```powershell
aws eks delete-addon --cluster-name hybrid-toy-eks --addon-name amazon-cloudwatch-observability --region ap-northeast-2
aws iam detach-role-policy --role-name hybrid-toy-eks-cwagent-role --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
aws iam delete-role --role-name hybrid-toy-eks-cwagent-role
```

로그 그룹은 보존 7일이라 방치해도 자동 소멸하나, 즉시 정리하려면 `aws logs delete-log-group`.

### 10.6 OKD는 통합하지 않는다

OKD는 자체 모니터링 체계를 보유한다. Helm chart로 non-EKS 클러스터에도 CloudWatch Agent를 설치할 수 있으나:

| 항목 | EKS | OKD |
|---|---|---|
| 인증 | Pod Identity (자동 회전) | **정적 IAM User access key** — CR에 수동 마운트 |
| Enhanced observability | ✅ | ❌ 컨트롤플레인·kube-state 메트릭 없음 |
| SCC | 무관 | `hostPath`/`hostNetwork` 요구 → SCC 부여 필요 |
| 업그레이드 | 애드온 라이프사이클 | 수동 |

동일한 대시보드가 나오지 않으면서 정적 자격증명을 하나 더 만든다. **비용 대비 이득이 없다.** 하이브리드 단일 관측 파이프라인은 백로그로 둔다(§16.3).

### 10.7 미도입 — Alarm

RDS CPU/Connections, EKS 노드 CPU/Memory, ALB 5xx 알람은 설계만 하고 구성하지 않았다. §16.3 백로그.

---
## §11. 트러블슈팅 지식베이스

> 전부 **실측 기반**이다. 새 사고를 발견하면 이 절에 추가한다.

### 11.1 인프라 · 네트워크 · Cloudflare

| 증상 | 원인 | 해결 |
|---|---|---|
| ACM 인증서 영구 **Pending Validation** | 검증 CNAME이 🟠 주황(프록시) | ⚪ 회색(DNS only)로 변경 |
| 브라우저 **무한 리다이렉트 루프** | Cloudflare SSL 모드 Flexible | **Full (strict)** |
| ALB Target Group **unhealthy** 영구 | `/healthz` 미구현 또는 경로 불일치 | 엔드포인트 구현 + annotation 경로 대조 |
| **`/` 로만 라우팅되고 API가 Web으로 감** | Ingress에서 `/` 를 먼저 선언 | `/` 를 **마지막**으로 이동 (§6.9) |
| OKD에서 **HTML 로그인 페이지** 수신 | Access Policy Action이 `Allow` | **`Service Auth`** |
| 노드 영구 `NotReady` → `NodeCreationFailure` | 애드온 `before_compute` 미지정 → CNI 부재 | `vpc-cni`·`eks-pod-identity-agent` 에 `before_compute = true` (§1.4) |
| LBC **CrashLoop** | 런타임 자동탐색이 IMDS `hop_limit=1` 과 충돌 | `region`/`vpcId` **명시 주입** (§8.7) |
| `terraform init` 실패 | `backend.tf` ↔ 부트스트랩 버킷명 불일치 | 값 일치 확인 |
| apply 중단 (SG 생성 시점) | SG `description` 에 한글 | ASCII만 (§8.6) |
| 매 plan마다 파라미터 그룹 diff | AWS가 `ON` 을 `1` 로 정규화 | `value = "1"` (§8.2) |
| **ARN이 `arn:aws:ia` 로 절단** | 멀티라인 백틱 명령 붙여넣기 | `output -raw` → 변수 → 1줄 (§12.2) |
| 도메인에 `[...](...)` 혼입 | 렌더링된 마크다운 복사 | 동일 |

### 11.2 데이터베이스 · ICD 적재

| 증상 | 원인 | 해결 |
|---|---|---|
| **WAS 커넥션 100% 실패** | JDBC TLS 옵션 누락 | `sslMode=REQUIRED` (§8.2) |
| `app_was` **`Access denied`** (비밀번호는 정확) | `REQUIRE SSL` 계정에 비TLS 접속 | 로컬 compose도 `sslMode=REQUIRED`. `DISABLED` 금지 |
| **`SELECT command denied to user 'app_was'`** | 신규 테이블 GRANT 누락 | `02_grants.sql` 에 추가 후 재실행 (§9.2) |
| **`ERROR 1147 ... no such grant`** | DB 단위 GRANT를 테이블 단위로 REVOKE 시도 | MySQL 미지원. 테이블 단위 명시 부여로 전환 (§9.2) |
| **ICD seed 적재 0건** | `완전코드구분='Y'` 로 필터 (**원본에 `Y`가 없다**) | `<> 'N'` 으로 교정 (§6.10) |
| **ICD seed `Duplicate entry`** | 마스터 테이블에 37,543행 전량 INSERT | 마스터 14,283 / 동의어 37,543 분리 (§6.8) |
| **상병코드 한글이 `???`** | seed 파일 BOM 또는 `SET NAMES` 누락 | UTF-8(BOM 없음) + `SET NAMES utf8mb4;` |
| **`ERROR 1451` — ICD 재적재 실패** | `DELETE FROM icd_code` 를 차트 존재 상태에서 실행 | UPSERT 방식 (§6.10) |
| **적재는 됐는데 검색이 느림** | `ANALYZE TABLE` 누락 → 통계가 3행으로 인식 | `ANALYZE TABLE icd_code, icd_code_synonym;` |
| **`/staff/icd-codes` 응답 수 초** | `name_kr` 인덱스 없음 → 풀스캔 | §6.8 인덱스 3종 생성 후 `EXPLAIN` |
| RDS 접속 timeout | ① 파드가 `app` 네임스페이스인지 ② RDS SG ③ 엔드포인트 오타 | 순서대로 확인 |
| RDS 접속 즉시 거부 | TLS 옵션 누락 | §8.2 |

### 11.3 애플리케이션 — Spring Boot 4 / Security 7 / Jackson 3 이관

> **Boot 3 관용구를 그대로 옮기면 기동 시점에 터진다.** 표면이 넓은 BFF에 집중됐다.

| 증상 | 원인 | 해결 |
|---|---|---|
| **`Could not find com.nimbusds:nimbus-jose-jwt:`** (버전 공백) | **Boot 4.1 BOM이 nimbus-jose-jwt를 관리하지 않는다.** Boot 3.x는 관리했다 | `build.gradle.kts` 에 `10.9.1` 명시 |
| **`cannot find symbol: AntPathRequestMatcher`** | **Security 7에서 제거** (6.5 deprecated) | 문자열 오버로드 또는 `PathPatternRequestMatcher`. URI는 **절대경로** |
| **`No qualifying bean of type 'RestClient$Builder'`** | **Boot 4는 자동 구성을 기능별 모듈로 분리.** `starter-web` 이 가져오지 않는다 | `spring-boot-starter-restclient` 추가 |
| **`LenientObjectToEnumConverterFactory` `IllegalArgumentException`** | **Jackson 3에서 `WRITE_DATES_AS_TIMESTAMPS` 가 `SerializationFeature` → `DateTimeFeature` 로 이동** | 해당 프로퍼티 **삭제**. Jackson 3 기본값이 이미 ISO-8601 |
| **`wrong column type ... found [text], expecting [tinytext]`** | `@Lob` 만 붙이고 `length` 미지정 → 기본 255 적용 | `@Column(length = 65535)` (§6.8) |
| **`wrong column type ... found [tinyint unsigned], expecting [integer]`** | `TINYINT`/`SMALLINT` 를 `int` 로 매핑 | DDL을 `INT` 로 통일. **Hibernate는 첫 불일치에서 멈추므로 전 컬럼을 한 번에 점검** |
| **`class, interface, enum, or record expected`** + `illegal character` | **Javadoc의 `**/` 가 `*/` 로 해석되어 주석 조기 종료.** 이후 한글이 코드로 파싱됨 | `**/` 제거. 커밋 전 전수 검색 |
| **`.\gradlew` 인식 안 됨** | 새 머신에 래퍼 없음 | `gradle wrapper --gradle-version 9.5.1`. 이후 **`.\gradlew` 만** 사용 |

### 11.4 애플리케이션 — 런타임 · 인증 · 통신

| 증상 | 원인 | 해결 |
|---|---|---|
| **환자 로그인은 되는데 API가 401** | 쿠키 `Path` 불일치 | `PATIENT_TOKEN` Path 확인 (§6.5) |
| **브라우저에서만 모든 POST가 403** (스크립트는 통과) | **`XSRF-TOKEN` Path를 축소했다.** `document.cookie` 는 현재 문서 경로 쿠키만 반환하는데 화면은 `/` 에서 열린다 | `XSRF-TOKEN` Path는 **`/`** (§6.5) |
| **환자 POST가 두세 번째부터 403** | CSRF 토큰을 1회만 읽어 캐시 | 매 요청 직전 쿠키 재조회 |
| **쿠키를 못 읽음** (검증 스크립트) | `CookieContainer.GetCookies(루트)` 는 경로 제한 쿠키를 반환하지 않는다 | 조회 URI에 경로 포함. **계약이 아니라 조회 쪽이 틀린 것** |
| **로그인 5회 실패 잠금 미작동** | 예외가 트랜잭션을 롤백해 카운터 증가분이 사라진다. **응답은 정상이라 어떤 시나리오도 못 잡는다** | `REQUIRES_NEW` 별도 빈 (§6.5) |
| **401만 본문이 빔** (409·400은 정상) | `SimpleClientHttpRequestFactory` 가 401을 인증 협상으로 보고 에러 스트림을 소비 | `JdkClientHttpRequestFactory` (§6.6) |
| **BFF 경유 한글 검색만 0건** (WAS 직접은 정상) | **URI 이중 인코딩** (`%` → `%25`) | 쿼리 값은 URI 템플릿 변수로 (§6.6) |
| **오류 응답에 `X-Trace-Id` 없고 `trace_id: null`** | `response.reset()` 이 설정된 모든 헤더를 삭제 | `reset()` 금지 (§6.7) |
| **필터가 만든 403의 본문이 빔** | 필터는 DispatcherServlet 밖 — `getWriter()` 커밋 시점이 컨테이너에 좌우됨 | 바이트 + `setContentLength` + `flushBuffer()` |
| **파드 기동 직후 첫 요청만 `503`** | WAS 콜드스타트가 read timeout 5초 초과 | 타임아웃 계약 유지. `startupProbe` + 워밍업 요청 |
| **예약 목록엔 뜨는데 예약하면 `400 invalid_date`** | 조회는 날짜 범위, 검증은 현재 시각 기준 | 조회 시작점을 `max(00:00, now)` (§6.6) |
| **응답 한글이 `êµ¬ì¤í¼í`** | nginx가 `Content-Type` 에 charset 미부착 | `charset utf-8;` (§6.7) |
| BFF 401 반복 | 전달수단 ↔ actor_type 불일치 | §6.5 |
| BFF 503 `upstream_unavailable` | WAS Pod 상태 / `was-svc` endpoints | 확인 |

### 11.5 배포 · 운영

| 증상 | 원인 | 해결 |
|---|---|---|
| 파드 `exec format error` | ARM 이미지 빌드 | `--platform linux/amd64` 재빌드 |
| **롤아웃이 `0 out of N new replicas` 에서 멈추고 파드가 0개** | **ResourceQuota `limits.cpu` 소진.** 파드가 생성되지 않아 `describe pod`·`describe rs`·로그·이벤트가 전부 비어 있다 | `kubectl -n app describe resourcequota` — **유일한 단서** (§6.4) |
| **`Apply failed with N conflicts: kubectl-client-side-apply`** | 과거 client-side apply 리소스의 필드 소유권 잔존 | `--force-conflicts` 로 소유권 인수 |
| `ImagePullBackOff` | ① 태그 오타 ② ECR 리포지토리 존재 ③ 노드 IAM ECR 권한 | 순서대로 |
| `CrashLoopBackOff` | ① `logs --previous` ② 아키텍처 불일치 ③ 필수 환경변수 누락 | 순서대로 |
| `endpoints` 비어 있음 | Service `selector` ↔ Pod `labels` 불일치 | 라벨 대조 |
| 서비스 간 호출 timeout | ① 대상 Pod Running ② Service 포트 ③ DNS 이름 오타 | 순서대로 |

### 11.6 도구 · 환경 (PowerShell 5.1 / Gradle / 검증 스크립트)

| 증상 | 원인 | 해결 |
|---|---|---|
| **`utf8NoBOM 을 유효한 열거자 이름과 일치시킬 수 없습니다`** | `-Encoding utf8NoBOM` 은 **PS 7 전용** | §12.1 표준 방식 |
| **`Set-Content -Encoding UTF8` 이 파일을 손상** | PS 5.1은 **BOM을 붙이고** 원본을 CP949로 읽는다 | 동일 |
| **`.ps1` 실행 시 한글이 깨짐 (`寃쎈줈`)** | **PS 5.1은 BOM 없는 `.ps1` 을 CP949로 파싱한다.** `[Console]::OutputEncoding` 으로는 안 잡힌다 | `.ps1` 은 **UTF-8 BOM + CRLF** 로 저장 |
| **`ConvertFrom-Json` 실패 (maxJsonLength)** | PS 5.1의 19MB JSON 파싱 한계 | `pwsh`(PS7)로 실행 |
| **`NativeCommandError` 로 스크립트 즉시 중단** (실패가 아닌데도) | `$ErrorActionPreference='Stop'` 에서 네이티브 명령의 stderr 한 줄이 종료 오류로 승격 | `'Continue'` + 판정은 **전부 `$LASTEXITCODE`** |
| **`-target` 파싱 오류** (`Prefix "module." must be followed by...`) | PowerShell 인용 | `"-target=module.ecr"` |
| **Gradle 테스트 로그 한글 깨짐** | 데몬·테스트 JVM의 `file.encoding` 이 CP949 | `-Dfile.encoding=UTF-8` + `Test { defaultCharacterEncoding = "UTF-8" }` |
| **테스트 실패 원인 메시지가 안 보임** | Gradle 기본 출력은 예외 클래스명만 | `testLogging { exceptionFormat = FULL; showCauses = true }` |
| **검증 스크립트 전 항목이 `status=-1`** | `docker compose up -d` 는 컨테이너 **시작** 시점에 반환. Spring Boot 기동에 15초 더 필요 | `up -d --wait`. **전 항목 동일 실패는 연결 문제의 신호다** |
| **G3 검증: `status=403` 인데 FAIL** | **Cloudflare Access의 차단 응답이 `text/html`**(자체 오류 페이지)인데 이를 "Allow 신호"로 오판 | 판정은 **상태코드만**. `302`/`200` 은 별도 항목으로 분리 |
| **PC 이동 후 `Module not installed`** | `.terraform/` 는 로컬 캐시 | `init` 재실행 |
| **`localhost:8080` 폴백** | kubeconfig 미등록. **클러스터 장애 아님** | `aws eks update-kubeconfig`. PC를 옮기면 매번 필요 |
| **`$env:AWS_PROFILE` 소실** | 세션 스코프 | apply 직전 `sts get-caller-identity` |

### 11.7 진단 명령

```bash
kubectl get nodes -o wide
kubectl -n app get events --sort-by=.lastTimestamp
kubectl -n app describe pod <파드명>            # ImagePull/CrashLoop 원인
kubectl -n app logs <파드명> --previous         # 재시작 직전 로그
kubectl -n app get endpoints                    # 비어 있으면 셀렉터 라벨 불일치
kubectl -n app describe resourcequota app-quota # 파드가 0개일 때 유일한 단서
kubectl -n app describe ingress patient-web
kubectl -n kube-system logs deploy/aws-load-balancer-controller
kubectl -n app logs deploy/cloudflared

# 클러스터 내부 통신
kubectl -n app run tmp --rm -it --image=curlimages/curl --restart=Never -- \
  curl -v http://bff-svc.app.svc.cluster.local:8080/healthz

# DNS 해석
kubectl -n app run tmp --rm -it --image=busybox --restart=Never -- \
  nslookup bff-svc.app.svc.cluster.local
```

**외부 흐름1 경로 검증**

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://www.kuspitalsoldeskproject.org/
curl -s -o /dev/null -w "%{http_code}\n" https://www.kuspitalsoldeskproject.org/api/bff/patient/auth/csrf
curl -s -o /dev/null -w "%{http_code}\n" https://www.kuspitalsoldeskproject.org/api/bff/staff/auth/login   # 404 여야 정상
```

### 11.8 배포 롤백

```powershell
kubectl -n app rollout history deploy/<서비스>
kubectl -n app rollout undo deploy/<서비스>
kubectl -n app rollout status deploy/<서비스>
```

> 이미지가 `IMMUTABLE` + git SHA 태그이므로 **어느 커밋인지 즉시 역추적된다.** 이것이 §7.5의 실효다.

---

## §12. 반복 실패 패턴과 표준 대응

> 개별 사고는 §11에 있다. 이 절은 **여러 번 반복되어 원칙으로 승격된 것**만 담는다.

### 12.1 PowerShell 5.1 파일 입출력 — 5회 반복

`utf8NoBOM` 미지원 / BOM 없는 `.ps1` 을 CP949로 파싱 / `Get-Content -Raw` 가 CP949로 읽음 / `Set-Content -Encoding UTF8` 이 BOM 추가 / `.NET` 이 PowerShell 현재 위치를 모름.

> **표준:** 파일 치환은 `[System.IO.File]::ReadAllText/WriteAllText` + `Resolve-Path` + `UTF8Encoding($false)`.
> **`.ps1` 자체는 UTF-8 BOM + CRLF 로 저장한다.**

```powershell
[System.IO.File]::WriteAllText($abs, $text, (New-Object System.Text.UTF8Encoding($false)))
Format-Hex $abs | Select-Object -First 1     # 첫 바이트가 EF BB BF 면 실패
```

**적용 대상:** SQL seed · YAML 매니페스트 · Dockerfile · **AWS CLI에 넘기는 JSON**(§10.1).

### 12.2 식별자 입력 — 3회 반복, 가장 비쌌던 교훈

`alb_domain_name` 오염과 LBC ARN 절단은 **원인이 같다.** 값이 아니라 **입력 경로**가 문제였다 — 렌더링된 텍스트를 콘솔에 붙여넣었다.

> **표준:** ARN·도메인·토큰·digest는 `terraform output -raw` 또는 `aws ... --output text` → **변수** → **단일 행 명령**.
> 문서의 표에서 값을 복사하지 않는다. 멀티라인 백틱 명령에 식별자를 넣지 않는다.
> 적용 직후 **명령으로 대조**한다. Helm `deployed` / Terraform `apply complete` 는 값의 정확성을 증명하지 않는다.

### 12.3 Terraform 검증 — plan 육안 검토가 유일한 방어선

`validate` 통과는 문법만 증명한다. apply 전 `plan.txt` 를 만들어 대조한다.

```powershell
terraform plan -out=tfplan
terraform show -no-color tfplan > plan.txt
```

| # | 검색어 | 기대값 |
|---|---|---|
| 1 | `aws_eks_addon.before_compute` | **2건** |
| 2 | `aws_route_table.database` | **1건 생성** |
| 3 | `domain_name` | 평문 도메인. 대괄호·`http` 없음 |
| 4 | `manage_master_user_password` | `true` / `password` 항목 부재 |

**코드 점검 (`envs/dev` 기준)**

```powershell
Get-ChildItem ..\..\modules -Recurse -Filter "*.tf" | Select-String "before_compute"
Select-String -Path ..\..\modules\network\main.tf -Pattern "create_database_subnet_route_table"
Get-ChildItem ..\..\modules -Recurse -Filter "*.tf" | Select-String "manage_master_user_password|^\s*password\s*="
Select-String -Path .\main.tf -Pattern "kusweb|kusbff|kuswas|kusdb"
Select-String -Path ..\..\modules\*\*.tf -Pattern "description" | Select-String "[가-힣]"
```

**모듈 사용 원칙**

- 모듈 기본값을 의도와 같다고 가정하지 않는다. **반드시 문서를 확인한다** (CNI 미설치가 여기서 나왔다).
- 설계 문장마다 **대응하는 인자를 코드에서 확인한다** ("완전 격리"라고 써놓고 NAT를 공유하고 있었다).
- 모듈 인자는 **호출부 + 선언부** 양쪽에 있어야 한다.
- `.terraform/` 하위의 deprecated 경고는 **우리 코드가 아니다.** 조치 불필요.
- state가 비었어도 AWS 실물을 확인한다. orphan 과금 + `AlreadyExists` 의 원인이다.

### 12.4 검증 하네스의 한계 — 통과가 동작을 보증하지 않는다

`verify-bff.ps1` 45/45 + `verify-flow1.ps1` 22/22 를 통과한 상태에서 **브라우저 회원가입이 403으로 실패했다.**

| 하네스가 브라우저보다 관대한 지점 | 결과 |
|---|---|
| 쿠키 조회 시 경로를 지정할 수 있다 | Path 결함을 놓친다 |
| `Secure` 속성을 강제하지 않는다 | http에서도 쿠키가 저장된다 |
| `SameSite` 를 해석하지 않는다 | 미검증 영역으로 남는다 |

> **원칙: 사람이 브라우저로 통과하기 전에는 흐름1 게이트를 닫지 않는다.**
> 스크립트는 회귀 방지 도구이지 최종 판정자가 아니다.

### 12.5 검증 실패를 만나면 기대값부터 의심한다

G3 최초 실행에서 2건 FAIL이 났으나 **인프라는 처음부터 정상이었다.** 상태코드는 기대값과 정확히 일치했고, 판정 로직에 `Content-Type` 조건을 임의로 덧붙인 것이 원인이었다.

> 계약이 요구한 것은 "브라우저 로그인 흐름으로 새지 않는다" 이지 "오류 응답이 JSON이어야 한다" 가 아니었다. 후자는 근거 없이 추가된 조건이다.
> **검증 실패를 발견하면 먼저 "무엇을 기대했는가" 를 계약과 대조한다.**

### 12.6 실패는 배치 안에서 닫는다

코드 산출을 배치로 끊고, 각 배치에 **검증 스크립트를 함께** 낸다. 코드만 받고 검증을 나중에 만들면 "동작하는 것처럼 보이는 상태"가 누적된다. 실패를 다음 배치로 넘기면 원인이 섞인다.

---
## §13. 금지 사항

| # | 금지 행위 | 이유 |
|---|---|---|
| 1 | 인프라 리드 외 인원의 `terraform apply` | 단일 state 손상 |
| 2 | `backend-bootstrap` 재실행 | `prevent_destroy` 충돌 |
| 3 | S3 state 버킷 수동 삭제 / 기존 backend에 `init -backend=false` | 버전 이력 = 유일한 포렌식 복구 수단 |
| 4 | `*.tfstate`, `*.tfvars`, 실제 Secret 커밋 | 자격증명 유출 |
| 5 | 이미지 `:latest` 태그 (**cloudflared 포함**) | `IMMUTABLE` 위반, 롤백 추적 불가 |
| 6 | RDS SG에 개인 IP 임시 허용 | 격리 설계 무력화 |
| 7 | DB 서브넷에 `kubernetes.io/*` 태그 | LBC가 DB 계층에 ENI 배치 |
| 8 | `admin` 계정을 앱에 직접 사용 | 최소 권한 위반 |
| 9 | 서비스 URL 코드 하드코딩 | 네임스페이스 변경 시 전면 재빌드 |
| 10 | 뼈대 완성 전 기능 추가 | 통합 지점 불안정화 |
| 11 | Cloudflare 설정을 Terraform으로 이관 | §0.4-2 위반 |
| 12 | **ALB Ingress에 `/api/bff/staff` 규칙 추가** | 직원 API 외부 노출 |
| 13 | **WAS에서 JWT 발급** | §6.5 책임 분리 위반 |
| 14 | **BFF에서 DB 직접 접근 / 비밀번호 해싱** | 동일 |
| 15 | **인증 POST 자동 Retry** | 중복 가입, 잠금 조기 발동 |
| 16 | **`roles` 배열 사용** | `role` 단수 문자열로 확정 |
| 17 | **비밀번호·토큰 로그 출력 / 인증 API body 전체 로깅** | 자격증명 유출. **CloudWatch Logs에 영속 저장된다** (§10.3) |
| 18 | **`kubectl delete -f k8s/`** | Namespace 포함 시 하위 전체 캐스케이드 삭제 |
| 19 | **`staff-api` DNS 레코드 수동 생성** | Tunnel 자동 생성분과 충돌 |
| 20 | **WAS 런타임에서 외부 공공데이터 API 직접 호출** | §7.11 단일 NAT SPOF 확대 |
| 21 | **처방 발급용 신규 API 경로 추가** | §7.12 검증 범위 재확대 |
| 22 | **`chart.icd_name_snapshot` 을 마스터 갱신에 맞춰 소급 수정** | 의료 기록 무결성 위반 |
| 23 | **`response.reset()` 호출** | 설정된 모든 헤더 삭제 — `X-Trace-Id`·`Set-Cookie` 소실 (§6.7) |
| 24 | **Application Signals 자동 계측 활성화** | 검증 완료 워크로드의 파드 스펙 변형 (§7.14) |
| 25 | **IMDS `http_put_response_hop_limit` 상향** | 파드의 노드 IAM 탈취 경로 개방 (§8.7) |

---

## §14. 온프레미스(OKD) 인터페이스 계약

> OKD팀은 **AWS 계정도, AWS 자격증명도, VPN도 전혀 필요 없다.**
> 실행 절차·DoD는 구축설명서에 있다. 이 절은 **인터페이스 계약**만 다룬다.

### 14.1 역할 경계

| 구분 | 내용 |
|---|---|
| ✅ OKD팀 담당 | Web Pod가 Cloudflare Access 엔드포인트를 **서버사이드에서 HTTPS 호출** |
| ✅ OKD팀 담당 | Service Token·직원 JWT를 **서버사이드에 보관** |
| ❌ 비담당 | cloudflared 배포 (EKS BFF 담당) |
| ❌ 비담당 | Tunnel 생성, Access App/Policy 구성 (인프라 리드) |
| ❌ 불필요 | VPN, IPsec, Direct Connect, 인바운드 방화벽 오픈 |

```
[사내망 OKD]                       [Cloudflare 엣지]           [AWS EKS]
Web Pod ──HTTPS 443──→ Access(Service Token 검증) → Tunnel ──→ cloudflared ──→ bff-svc
        (아웃바운드)                                         (아웃바운드로 사전 연결)
```

**양쪽 모두 아웃바운드 연결만** 한다. 엣지에서 두 연결이 만난다. 사내망에 인바운드 포트를 열 필요가 없다 — 이 아키텍처를 선택한 이유다.

### 14.2 호출 방식 — 2계층 인증

```bash
# 1계층: Cloudflare Access (Service Token)
# 2계층: BFF 직원 JWT (Bearer)
curl -s https://staff-api.kuspitalsoldeskproject.org/api/bff/staff/patients \
  -H "CF-Access-Client-Id: <CLIENT_ID>" \
  -H "CF-Access-Client-Secret: <CLIENT_SECRET>" \
  -H "Authorization: Bearer <STAFF_JWT>"
```

**두 Access 헤더 이름은 정확히 이대로여야 한다.**

| 실패 지점 | 상태 코드 | 판정 주체 |
|---|---|---|
| Service Token / Access 검증 실패 | **403** | Cloudflare / cloudflared |
| 직원 JWT 없음·만료·위조 | **401** | BFF |
| JWT 유효하나 역할 부족 | **403** | BFF |

> 📌 **401 JSON은 좋은 신호다.** Access를 통과해 BFF까지 도달했다는 뜻이다(JWT가 아직 없을 뿐).
> 📌 `302` 또는 `200 text/html` 이 오면 Access 구성 문제다 — 조치 주체는 **인프라 리드**.

### 14.3 애플리케이션 구현 요구사항

| # | 요구사항 | 이유 |
|---|---|---|
| 1 | Access 두 헤더를 **모든 요청**에 부착 | 누락 시 403 |
| 2 | 직원 로그인 후 JWT를 **서버사이드 세션**에 보관 | 브라우저 노출 방지 |
| 3 | 업무 API 호출 시 `Authorization: Bearer` 추가 | §6.5 |
| 4 | 토큰을 환경변수로 읽기. **코드·이미지 하드코딩 금지** | 유출·로테이션 불가 |
| 5 | 토큰 **로그 출력 금지** | 자격증명 유출 |
| 6 | HTTP 타임아웃 (connect 5s / read 30s) | 엣지 경유로 홉 증가 |
| 7 | 재시도 2~3회 지수 백오프. **단 인증 POST는 재시도 금지** | Rate Limit / 계정 잠금 |
| 8 | 응답 `Content-Type` 검증 | 인증 실패 시 HTML이 온다 |
| 9 | 직원 로그아웃 시 세션·JWT 삭제 | |
| 10 | 직원 JWT 만료(8h) 시 재로그인 유도 | Refresh Token 미구현 |
| 11 | 표준 enum(`BOOKED` 등) → **한글 라벨 변환은 OKD Web이 수행** | §6.8 |

### 14.4 사내 프록시 / TLS 검사 대응

```yaml
env:
  - name: HTTPS_PROXY
    value: "http://proxy.internal:3128"
  - name: NO_PROXY
    value: "localhost,127.0.0.1,.svc,.cluster.local"
```

프록시가 TLS MITM 검사를 하면 **사내 CA를 ConfigMap으로 마운트**하고 언어별 신뢰 저장소에 등록한다. 미조치 시 `certificate verify failed` 로 전부 실패한다.

> ⚠️ 방화벽 정책 변경은 사내 승인에 며칠이 걸린다. **가장 먼저 착수한다.**

### 14.5 API 스펙 합의 절차

> **경로 분리로 확정되었다.** OKD Web은 `/api/bff/staff/**` 만 호출한다. `/api/bff/patient/**` 호출 금지.
> API 스펙은 **§6.6 계약이 전부다.** 별도 합의 절차 없음.

---

## §15. 확정 결정 로그

> **이 표의 항목은 재논의하지 않는다.** 변경하려면 이 문서를 먼저 고치고 PR을 올린다.
> 확정 일자는 구축설명서에 있다.

| # | 항목 | 확정 | 근거 | 페이즈 |
|---|---|---|---|---|
| 1 | RDS TLS 강제 | 적용 (`require_secure_transport`) | §8.2 | P0 |
| 2 | RDS 마스터 비밀번호 | Secrets Manager | §8.3 | P0 |
| 3 | RDS CMK | 미적용 (백로그) | 오버스펙 | P0 |
| 4 | ECR 태그 정책 | `IMMUTABLE` | §7.5 | P0 |
| 5 | 내부 도메인 | `staff-api.kuspitalsoldeskproject.org` | — | P0 |
| 6 | Kubernetes | `1.35` | 표준 지원 구간 | P0 |
| 7 | LBC Chart | `3.5.0` 고정 | §8.7 | P1 |
| 8 | 파라미터 값 표기 | `require_secure_transport = "1"` | drift 제거 | P1 |
| 9 | Ingress 경로 | 2-path, `/` 마지막 | §6.9 | P1 |
| 10 | 직원 API ALB 등록 | **금지** | §0.2 | P1 |
| 11 | cloudflared 이미지 | digest 핀 (`:latest` 금지) | §13-5 | P1 |
| 12 | JDBC TLS 옵션 | `sslMode=REQUIRED` | Connector/J deprecated | P1 |
| 13 | JWT 발급 주체 | **BFF 단독.** WAS 발급 금지 | §6.5 | P1 |
| 14 | 역할 claim | `role` 단수 문자열 | §6.5 | P1 |
| 15 | 환자/직원 JWT TTL | 30분 / 8시간 | §6.5 | P1 |
| 16 | DB PK 명명 | `patient_id` / `staff_id` 유지 | §6.8 | P1 |
| 17 | 직원 활성 컬럼 | `status ENUM` 유지, `ACTIVE` 만 로그인 | §6.8 | P1 |
| 18 | `must_change_password` | `DEFAULT 0` | §6.8 | P1 |
| 19 | 예약 상태 표현 | WAS는 표준 enum 반환. 한글 라벨은 각 Web | §6.8 | P1 |
| 20 | X-Actor 검증 | BFF 1차 + WAS 2차 (불일치 403) | §6.6 | P1 |
| 21 | BFF `/readyz` | WAS에 종속시키지 않는다 | §7.9 | P1 |
| 22 | Access JWT 검증 | Dashboard Protect with Access. BFF 미검사 | §7.10 | P1 |
| 23 | Java / Spring Boot / Gradle | 25 / 4.1.0 / 9.5.1 | §5.3 | P1 |
| 24 | patient-web 베이스 | `nginx-unprivileged` (8080·non-root), `1.27-alpine` 고정 | §5.3 | P1 |
| 25 | CORS | 추가하지 않음 (동일 도메인) | §6.9 | P1 |
| 26 | NetworkPolicy | 백로그 | §16.3 | P1 |
| 27 | 공공데이터 적재 방식 | **오프라인 seed 1회.** WAS 런타임 호출 금지 | §7.11 | P1 |
| 28 | ICD 적재 필터 | `완전코드구분<>'N' AND 주상병사용구분<>'N'` → 마스터 14,283 / 동의어 37,543 | §6.10 | P1 |
| 29 | ICD 테이블 구조 | `icd_code` + `icd_code_synonym` **2테이블 분리** | §6.8 (코드 중복 6,785종) | P1 |
| 30 | 처방 발급 API | `POST /api/bff/staff/charts` **단일 트랜잭션.** 신규 경로 없음 | §7.12 | P1 |
| 31 | 상병명 보관 | `chart.icd_name_snapshot` 발급 시점 복사. 소급 수정 금지 | §6.8 | P1 |
| 32 | DB 숫자 컬럼 | `TINYINT`/`SMALLINT` 미사용. **`INT` 로 통일** | §6.8 | P2 |
| 33 | `chart.note` 매핑 | `@Lob` + **`length = 65535`** (MySQL `TEXT`) | §6.8 | P2 |
| 34 | 예약 가능 슬롯 기준 | `max(조회일 00:00, now)` — 조회와 생성의 판정 일치 | §6.6 | P2 |
| 35 | 로컬 통합 기동 | `docker compose up --build -d --wait` | 구축설명서 | P2 |
| 36 | Nimbus JOSE+JWT 버전 | **`10.9.1` 명시 핀.** Boot 4.1 BOM 미관리 | §5.3 | P2 |
| 37 | BFF starter 구성 | `web`+`security`+`validation`+**`restclient`**. `data-jpa` 미포함(§6.5를 의존성으로 강제) | §5.3 | P2 |
| 38 | BFF → WAS HTTP 클라이언트 | **`JdkClientHttpRequestFactory`.** `Simple...` 은 401 본문을 삼킨다 | §6.6 | P2 |
| 39 | BFF 아웃바운드 URI | 쿼리 값은 **URI 템플릿 변수**로만. 문자열 연결·사전 인코딩 금지 | §6.6 | P2 |
| 40 | 로그인 실패 카운터 | `REQUIRES_NEW` 별도 트랜잭션(`LoginAttemptService`) | §6.5 | P2 |
| 41 | 오류 응답 작성 | `response.reset()` 금지. `trace_id` 는 절대 null 미출력 | §6.7 | P2 |
| 42 | 파드 CPU limits | WAS·BFF **500m**. ResourceQuota `limits.cpu: 6` | §6.4 | P2 |
| 43 | server-side apply | `--force-conflicts` 사용. 매니페스트가 단일 권위 | §11.5 | P2 |
| 44 | CSRF 쿠키 Path | **`/`** (JS가 읽어야 한다). `PATIENT_TOKEN` 만 `/api/bff/patient` 로 축소 | §6.5 | P2 |
| 45 | **관측성 방식** | **CloudWatch Observability EKS 애드온.** Prometheus/Grafana 자체 운영 미채택 | §7.13 | P3+ |
| 46 | **CW Agent 인증** | **EKS Pod Identity** (IRSA 아님). Role `hybrid-toy-eks-cwagent-role` | §10.1 | P3+ |
| 47 | **Application Signals** | **비활성** (`monitorAllServices: false`). 파드 스펙 불변 유지 | §7.14 | P3+ |
| 48 | **가속 컴퓨팅 메트릭** | 비활성. t3.medium — 수집 대상 부재 | §10.1 | P3+ |
| 49 | **로그 보존기간** | **7일.** 기본값(무제한)에서 하향 | §10.3 | P3+ |
| 50 | **OKD 관측성 통합** | **미통합.** OKD 자체 체계 유지. 정적 키 도입 회피 | §10.6 | P3+ |
| 51 | **CW 애드온 관리 방식** | **CLI 관리 (Terraform 미편입).** state 밖 리소스로 destroy 시 수동 정리 | §10.5 | P3+ |

---

## §16. 백로그 및 운영 전환 요건

**뼈대 완성 전에는 착수하지 않는다.** 확정된 항목은 §15를 본다.

### 16.1 운영 전환 시 필수 변경

| 항목 | 현재 | 변경 후 |
|---|---|---|
| NAT Gateway | 단일 | AZ당 1개 |
| RDS Multi-AZ | `false` | `true` |
| `skip_final_snapshot` | `true` | `false` |
| EKS 엔드포인트 | public + private | private 전용 또는 CIDR 제한 |
| EKS 접근 권한 | 전원 ClusterAdmin | 네임스페이스 스코프 |
| JDBC `sslMode` | `REQUIRED` | `VERIFY_CA` + RDS CA 번들 |
| Secret 관리 | K8s Secret 수동 | External Secrets Operator |
| kusdb Secrets Manager 권한 | 인라인 정책 | 관리형 정책 |
| CloudWatch 애드온 | CLI 관리 | `aws_eks_addon` 으로 Terraform 편입 |
| 로그 보존 | 7일 | 규정 요건에 맞게 상향 + S3 아카이빙 |

### 16.2 미해결 항목

| # | 항목 | 영향 | 처리 |
|---|---|---|---|
| 1 | `SameSite=Lax` 실동작 미검증 | 외부 링크 진입 흐름 | 브라우저 수동 확인 필요. 스크립트로는 판정 불가 |
| 2 | 브라우저 콘솔의 초기 401 1회 | 없음. **의도된 동작** | §16.4 참조 |
| 3 | `UserDetailsServiceAutoConfiguration` 경고 | 없음 | 명시적 비활성화 검토 |
| 4 | 검증 스크립트 한글 정렬 깨짐 | 로그 오독 위험 | 한글은 폭이 2. 표시 폭 기준 패딩으로 교체 |
| 5 | RDS에 검증 데이터 잔존 | 시연 데이터와 혼재 | 정리 여부 판단 |
| 6 | WAS/BFF `startupProbe` 150초 | 과대 설정 | 실측 기동 12~15초 |
| 7 | `patient-web` 화면 최소 구현 | 예약 취소·진료 기록 조회 미구현 | |
| 8 | `amazoncloudwatchagent` CR의 `VERSION 0.0.0` 표시 | 없음 (파드 정상 Running) | CR 상태 필드 표시 이슈로 추정. 미조사 |
| 9 | Cluster Autoscaler 미설치 | 노드그룹 max=3이 **비활성 상태** | 리소스 부족 시 desired 수동 상향 |

### 16.3 기능 백로그

**인프라·운영**
- **CloudWatch Alarm** — RDS CPU/Connections, 노드 CPU/Memory, ALB 5xx, 파드 재시작/Pending
- `metrics-server` — `kubectl top` 활성화
- EKS 컨트롤플레인 로그 활성화
- **하이브리드 단일 관측 파이프라인** — OKD ↔ CloudWatch 통합 (§10.6)
- NetworkPolicy — cloudflared→BFF, BFF→WAS, WAS→RDS만 허용
  > L3/L4 통제다. `/api` 경로 같은 L7 통제를 대신하지 않는다. 경로 통제는 ALB Ingress · Cloudflare Access · BFF Security가 담당한다.
- mTLS / Service Mesh
- CI/CD (GitHub Actions → ECR → EKS)
- HPA / Cluster Autoscaler / Karpenter
- RDS CMK
- VPC Endpoint (ECR, S3, Secrets Manager) — NAT 비용 절감
- 환경 분리 (`envs/stg`, `envs/prd`) 및 state 분리
- apex 도메인(`kuspitalsoldeskproject.org`) 처리

**인증·계정**
- Cognito / Refresh Token / MFA / JWT 키 회전 / 강제 폐기 목록
- 직원 최초 비밀번호 강제 변경, 관리자 수동 잠금 해제
- 다중 역할(`roles` 배열), `RECEPTION` / `BILLING` 역할

**도메인**
- **ICD 마스터 자동 동기화** — 공공데이터포털을 호출하는 일회성 `Job`/`CronJob`. WAS와 분리 필수(§7.11). 서비스키는 Secrets Manager 경유
- **의약품 표준코드 연동** — `prescription_item.drug_name` 을 FK로 승격
- **처방 수정·취소 API** — `PATCH`/`DELETE /api/bff/staff/charts/{id}` (§7.12의 대가)
- **부상병 다중 등록** — 현재 차트당 상병코드 1개
- **처방전 PDF 발급 / 전자서명**
- **ICD 검색 성능** — 부분일치 요구가 커지면 FULLTEXT + ngram 파서로 전환

### 16.4 알려진 정상 동작 — 브라우저 콘솔의 초기 401

`patient-web` 은 페이지 진입 시 `GET /api/bff/patient/appointments` 를 호출해 로그인 상태를 판정한다. 미로그인이면 401이 오고 가입 화면을 띄운다.

`PATIENT_TOKEN` 은 HttpOnly라 JS가 읽을 수 없다. **서버에 물어보는 것이 유일한 방법이다.** 브라우저는 `fetch` 의 4xx를 콘솔에 자동 출력하며 `catch` 로도 막을 수 없다.

대안을 검토했으나 전부 대가가 더 크다.

| 대안 | 대가 |
|---|---|
| `/auth/me` 신설 | 신규 경로 추가 — §7.12 위반 |
| `localStorage` 플래그 | 서버 상태와 어긋난다 |
| 초기 조회 제거 | 새로고침마다 로그아웃처럼 보인다 |

---

## §17. 확정 인프라 식별자

> ⚠️ **이 표에서 값을 복사해 쓰지 않는다.** 기록·대조용이다. 실제 입력은 §12.2 표준을 따른다.

| 항목 | 값 |
|---|---|
| AWS 계정 | `597106152264` |
| 리전 | `ap-northeast-2` |
| apply 주체 | `user/team03` |
| EKS 클러스터 | `hybrid-toy-eks` (Kubernetes `1.35`) |
| 네임스페이스 | `app` |
| S3 state 버킷 | `hybrid-toy-tfstate-kuspital` |
| 외부 도메인 (흐름1) | `www.kuspitalsoldeskproject.org` |
| 내부 도메인 (흐름2) | `staff-api.kuspitalsoldeskproject.org` |
| RDS 엔드포인트 | `hybrid-toy-rds.cfmws2co6i6j.ap-northeast-2.rds.amazonaws.com:3306` |
| ACM 인증서 | `arn:aws:acm:ap-northeast-2:597106152264:certificate/6eecdf13-ea45-4847-964b-ae9642308f87` |
| LBC IRSA 역할 | `arn:aws:iam::597106152264:role/hybrid-toy-eks-lbc-irsa` |
| CW Agent 역할 | `arn:aws:iam::597106152264:role/hybrid-toy-eks-cwagent-role` |

**ECR**

```
597106152264.dkr.ecr.ap-northeast-2.amazonaws.com/hybrid-toy/patient-web
597106152264.dkr.ecr.ap-northeast-2.amazonaws.com/hybrid-toy/bff
597106152264.dkr.ecr.ap-northeast-2.amazonaws.com/hybrid-toy/was
```

**네트워크 리소스 ID**

| 리소스 | ID |
|---|---|
| VPC | `vpc-0eaa396d5e9eae015` |
| Public Subnet | `subnet-0f55d9efac8f2b6b0`, `subnet-01ab1a42f616a2733` |
| Private Subnet | `subnet-03e4de8d6064f96a1`, `subnet-008571088a2c53a6f` |
| Database Subnet | `subnet-056a7517df20bb615`, `subnet-030857d1a7b2d75c9` |
| Database RT | `rtb-086678314e73d8b93` |
| NAT Gateway | `nat-07f604e7d0bbba903` |

**해석된 모듈 버전** — `aws 6.58.0` · `eks 21.24.2` · `vpc 5.21.0` · `iam 5.60.0` · `kms 4.0.0`

**kubeconfig 등록**

```powershell
aws eks update-kubeconfig --region ap-northeast-2 --name hybrid-toy-eks
```

> PC를 옮기면 매번 필요하다. 미등록 시 `localhost:8080` 폴백은 **클러스터 장애가 아니다.**

---

## 부록 A. 문서 번호 매핑

v3.2 이전 번호를 참조하는 코드 주석·스크립트·구 문서가 있다면 아래로 변환한다.

| v3.2 | v4.0 | 비고 |
|---|---|---|
| §0 프로젝트 개요 | §0 | 구축 결과 요약 통합 |
| §1 서비스 리스트 | §1 시스템 구성 | 확정 식별자는 §17로 분리 |
| §2 네트워크 설계 | §2 | 그대로 |
| §3 리포지토리 구조 | §3 | 그대로 |
| §4 협업 규칙 | §4 | 문서 갱신 규칙 통합 |
| §5 기술 스택 | §5 | digest 표 통합 |
| **§6 표준 및 계약** | **§6** | **번호 유지.** 6.11 파드 리소스 → 6.4로 통합 |
| **§7 설계상 핵심 판단** | **§7** | **번호 유지.** 7.13·7.14 신설 |
| §8 apply 전 선조치 | §8.4 / 구축설명서 | 권한 모델은 §8.4, 절차는 구축설명서 |
| §9 실행 순서 및 게이트 | §0.5 / 구축설명서 | 페이즈 구조는 §0.5, 게이트 절차는 구축설명서 |
| §10 인프라 리드 실행 절차 | 구축설명서 | 전량 이관 |
| §11 EKS팀 실행 절차 | 구축설명서 | Ingress 계약은 §6.9 |
| §12 DB팀 실행 절차 | **§9** | GRANT·접속 경로는 §9, 순서는 구축설명서 |
| §13 보안 및 암호화 | **§8** | IMDS·LBC 판단 추가 |
| §14 DoD 체크리스트 | 구축설명서 | 전량 이관 |
| **§15 트러블슈팅** | **§11** | 6개 카테고리로 재분류 |
| §16 금지 사항 | **§13** | 25개로 확장 |
| §17 백로그 | **§16** | 운영 전환 요건 통합 |
| §18 OKD 가이드 | **§14** | 인터페이스 계약만. 절차는 구축설명서 |
| §19 P0 기록 및 교훈 | §12 / 구축설명서 | 원칙은 §12, 기록은 구축설명서 |
| §20 P1 기록 및 교훈 | §8.7 / §12 / §17 | 판단·원칙·식별자로 분해 |
| §21 확정 결정 로그 | **§15** | 45~51 추가 |
| §22 P2·P3 실행 기록 | §0.6 / §12 / 구축설명서 | 결과는 §0.6, 원칙은 §12, 기록은 구축설명서 |
| — | **§10 관측성** | 신설 |

---

## 재개 시 시작점

1. **§15 확정 결정 로그** — 무엇이 이미 결정됐는지. 재논의 금지 항목.
2. **§6 표준 및 계약** — 코드가 지켜야 할 것. 이 시점 이후 변경되지 않았으므로 유효하다.
3. **§16 백로그** — 다음에 할 것.
4. **구축설명서** — 어떻게 만들었는지, 어떤 순서로 검증했는지.

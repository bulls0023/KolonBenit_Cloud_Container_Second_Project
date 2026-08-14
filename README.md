# Hybrid Toy Project — 팀 통합 가이드라인

> **이 문서는 프로젝트의 단일 진실 공급원(Single Source of Truth)이다.**
> 모든 팀원은 작업 시작 전 최소 §0 ~ §6 을 읽고, 본인 담당 섹션을 정독한다.
> 문서와 코드가 다르면 **문서가 틀린 것**이다. 발견 즉시 PR로 문서를 고친다.

| 항목 | 값 |
|---|---|
| 문서 버전 | **v3.2** |
| 대상 환경 | `dev` (단일 환경) |
| AWS 리전 | `ap-northeast-2` (서울) |
| 프로젝트 식별자 | `hybrid-toy` |
| 최종 갱신 | 2026-08-13 (🚩 **G3 통과 — 뼈대(G1~G3) 완성.** OKD Web 은 범위 밖 이관) |
| 하위 문서 | `구축설명서-v1.2.md` (산출물·역할·실행순서) |

### v3.1 → v3.2 변경 요약

> **P2 실행 기록 반영.** 계약(§6)은 두 곳만 바뀌었고, 나머지는 실행 결과와 교훈이다.

| # | 변경 | 근거 |
|---|---|---|
| 1 | **§22 신설 — P2 실행 기록 및 교훈** | WAS·BFF·Web 구현부터 G2 통과까지 |
| 2 | §6.5 CSRF 쿠키 `Path=/` 로 교정 | 브라우저 `document.cookie` 는 현재 문서 경로만 본다 (실측) |
| 3 | §6.2 `JWT_AUDIENCE` = `hybrid-toy-api` 재확인 | 코드가 `hybrid-toy` 였다. 배포 전 교정 |
| 4 | §9.4 게이트에 **W1 / W2 / B1 / B2** 추가 | 실제 검증 단위를 반영 |
| 5 | §11 파드 리소스 계약 확정 (`limits.cpu: 500m`) | ResourceQuota 소진으로 스케줄 실패 (실측) |
| 6 | §15 트러블슈팅 **20건 추가** | 전부 실측 기반 |
| 7 | §21 결정 로그 **#32 ~ #44** | 재논의 차단 |
| 8 | §17.3 백로그 갱신 | 미해결 항목 이관 |

### v3.0 → v3.1 변경 요약

> **범위: 진료·처방 도메인 1건.** 인증·네트워크·인프라 계약은 **전부 무변경**이다.
> Ingress(§6.9)·인증(§6.5)·Terraform·Cloudflare 설정은 이 개정으로 바뀌지 않는다. 재작업 대상이 아니다.

| # | 변경 | 근거 |
|---|---|---|
| 1 | **§6.8에 진료·처방 테이블 5종 확정** (`icd_code`, `icd_code_synonym`, `chart`, `prescription`, `prescription_item`) | 도메인 엔티티는 선언되어 있었으나 컬럼 계약이 없었다 |
| 2 | **§6.10 신설 — 공공데이터(KCD 상병코드) 적재 계약** | 적재 주체·시점·필터 기준이 미정의 상태였다 |
| 3 | **§7.11 신설 — WAS 런타임 외부 API 호출 금지** | 단일 NAT(§7.4) 위에 외부 의존을 얹으면 SPOF가 진료 기능까지 확대된다 |
| 4 | 처방 발급을 **`POST /api/bff/staff/charts` 단일 트랜잭션**으로 확정 (신규 경로 없음) | 경로 추가 시 Ingress·Security·cloudflared 검증을 다시 돌려야 한다 |
| 5 | §6.5 역할표 — DOCTOR 권한을 "차트·**처방** 작성"으로 명확화 | NURSE 403 판정 근거를 처방까지 확장 |
| 6 | §6.7 오류 코드 `409 duplicate_prescription` 추가 | 차트 1건당 처방 1건 UNIQUE의 응답 계약 |
| 7 | §16 금지 항목 **#19 / #20** 추가 | 위 3·4번의 강제 |
| 8 | §21 확정 결정 로그 **#27 ~ #31** 추가 | 재논의 차단 |

### v2.1 → v3.0 변경 요약

| # | 변경 | 근거 |
|---|---|---|
| 1 | **애플리케이션 계약 v2를 README에 흡수** (§6.5 ~ §6.9 신설) | 문서 2개가 서로를 참조하며 어긋나던 상태 해소 |
| 2 | Ingress를 **2-path 구조**로 교체 | 기존 예시에 `/api/bff/patient` 규칙이 없어 흐름1이 성립 불가 |
| 3 | cloudflared 이미지 `:latest` → **digest 핀** | §16-4 자기모순 제거 |
| 4 | JDBC TLS 옵션 `useSSL/requireSSL` → **`sslMode=REQUIRED`** | Connector/J 8.0.13+ 에서 deprecated |
| 5 | §18.11 "공통 API 공유 권장" **폐기** | v2에서 `/api/bff/staff/**` 분리로 이미 확정 |
| 6 | WAS의 JWT 발급 **전면 금지** 명문화 | v2 §23. WAS `JwtTokenProvider` 잔존 = 계약 위반 |
| 7 | 애플리케이션 스택 버전 **전량 핀** (§5.3 신설) | 인프라만 핀하고 앱은 부동이던 비대칭 해소 |
| 8 | `require_secure_transport` 값 `"ON"` → `"1"` | 상시 drift 제거 (§20.5) |
| 9 | §21 신설 — **확정 결정 로그** | 재논의 차단 |

---

## 목차

- [§0. 프로젝트 개요](#0-프로젝트-개요)
- [§1. 서비스 리스트](#1-서비스-리스트)
- [§2. 네트워크 설계](#2-네트워크-설계)
- [§3. 리포지토리 구조 및 소유권](#3-리포지토리-구조-및-소유권)
- [§4. 협업 규칙](#4-협업-규칙)
- [§5. 기술 스택 및 버전 고정](#5-기술-스택-및-버전-고정)
- [§6. 표준 및 계약](#6-표준-및-계약)
- [§7. 설계상 핵심 판단](#7-설계상-핵심-판단)
- [§8. apply 전 필수 선조치](#8-apply-전-필수-선조치-완료)
- [§9. 전체 실행 순서 및 게이트](#9-전체-실행-순서-및-게이트)
- [§10. 인프라 리드팀 실행 절차](#10-인프라-리드팀-실행-절차)
- [§11. EKS팀 실행 절차](#11-eks팀-실행-절차)
- [§12. DB팀 실행 절차](#12-db팀-실행-절차)
- [§13. 보안 및 암호화 기준](#13-보안-및-암호화-기준)
- [§14. 완료 기준(DoD) 체크리스트](#14-완료-기준dod-체크리스트)
- [§15. 트러블슈팅](#15-트러블슈팅)
- [§16. 금지 사항](#16-금지-사항)
- [§17. 백로그](#17-백로그)
- [§18. 온프레미스(OKD)팀 가이드](#18-온프레미스okd팀-가이드)
- [§19. P0 기록 및 교훈](#19-p0-기록-및-교훈)
- [§20. P1 실행 기록 및 교훈](#20-p1-실행-기록-및-교훈)
- [§21. 확정 결정 로그](#21-확정-결정-로그)

---

## §0. 프로젝트 개요

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

기능 추가 제안은 §17 백로그에 기록만 하고 착수하지 않는다.

### 0.4 전제 조건

| # | 조건 |
|---|---|
| 1 | 온프레미스 OKD 환경은 **이미 구성 완료** 상태 |
| 2 | Cloudflare 설정은 **대시보드 수동 작업** (cloudflared Pod 제외). Terraform 관리 대상 아님 |
| 3 | Git repo 1개를 전원이 공유. `terraform apply`는 **인프라 리드 1인 전담** |
| 4 | 팀별 state 분리 없음. 단일 state 운영 |
| 5 | S3 버킷은 **필수 옵션만** 사용 |

---

## §1. 서비스 리스트

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
| IRSA Role | `hybrid-toy-eks-lbc-irsa` | ✅ | 인프라 리드 |
| ECR ×3 | §1.1 | ✅ `modules/ecr` | 리드 생성 / EKS팀 사용 |
| RDS (MySQL 8.0) | `hybrid-toy-rds` | ✅ `modules/rds` | 리드 생성 / DB팀 운영 |
| ACM 인증서 | `var.alb_domain_name` | ✅ `envs/dev` | 인프라 리드 |
| S3 (tfstate) | `hybrid-toy-tfstate-kuspital` | ✅ `backend-bootstrap` | 인프라 리드 |
| **ALB** | Ingress가 동적 생성 | ❌ **K8s Ingress** | EKS팀 — Web |

> ⚠️ **ALB는 Terraform이 만들지 않는다.** §7.1 참조.

### 1.4 클러스터 애드온

| 애드온 | 설치 주체 | 방식 | 비고 |
|---|---|---|---|
| VPC CNI | Terraform | EKS Addon | **`before_compute = true` 필수** |
| EKS Pod Identity Agent | Terraform | EKS Addon | **`before_compute = true` 필수** |
| CoreDNS | Terraform | EKS Addon | 노드 기동 후 |
| kube-proxy | Terraform | EKS Addon | 노드 기동 후 |
| AWS Load Balancer Controller | 인프라 리드 | Helm (수동, 버전 고정) | Ingress → ALB 변환 |

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

### 2.3 RDS 접근 통제 — 삼중 방어

| 계층 | 통제 수단 | 상태 |
|---|---|---|
| 네트워크 | DB 전용 서브넷 + 전용 RT (NAT 라우트 없음) | ✅ |
| 방화벽 | SG — EKS 노드 SG 출처의 3306만 허용 | ✅ |
| 접근성 | `publicly_accessible = false` | ✅ |

**결과: 로컬 PC에서 RDS 직접 접속 불가.** DB팀은 §12.1 경로를 사용한다.

### 2.4 서브넷 분리 근거

| 근거 | 설명 |
|---|---|
| Defense in depth | SG 규칙 하나 잘못 수정해도 서브넷 경계가 2차 방어선 |
| IP 고갈 방지 | VPC CNI는 파드마다 ENI 보조 IP를 소비한다. 워커가 `/24`를 잠식하면 RDS 확장 시 IP 부족 |
| 감사 대응 | 의료 도메인. 데이터 계층 네트워크 분리는 사실상 필수 요건 |

> ⏱️ apply 후 서브넷 그룹을 바꾸면 `aws_db_subnet_group` 교체 → **RDS 재생성**이 트리거된다. 이 구조는 apply 전에 확정되었다.

### 2.5 DB 서브넷에 NAT 라우트를 붙이지 않은 이유

RDS는 아웃바운드 인터넷이 불필요하다. 향후 S3 export나 Lambda 연동이 필요해지면 **NAT가 아니라 VPC Endpoint**를 추가한다.

---

## §3. 리포지토리 구조 및 소유권

```
repo/
├── README.md                      # 이 문서 — 전원 필독
├── 구축설명서-v1.2.md              # 산출물·역할·실행순서
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
│   ├── 04_icd_seed.sql            # ★ v3.1 KCD 상병코드 적재 (생성물)
│   ├── raw/data.json              # ★ 공공데이터 원본 (19MB, 47,798행)
│   └── tools/
│       ├── gen-bcrypt.ps1
│       └── convert-icd.ps1        # ★ v3.1 data.json → 04_icd_seed.sql
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
└── scripts/build-push.ps1         # [EKS팀] 이미지 빌드·푸시
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

### 4.2 apply 전 필수 절차

```powershell
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

> `terraform apply` 단독 실행 금지. plan 파일을 거쳐야 검토한 내용과 실제 적용이 일치한다.

### 4.3 Git 규칙

| 항목 | 규칙 |
|---|---|
| 브랜치 | `feature/<team>-<내용>` (예: `feature/bff-nimbus-jwt`) |
| 커밋 | `[team] 내용` (예: `[db] commondb DDL 확정`) |
| PR | 본인 담당 디렉토리 외 파일 변경 시 해당 팀 리뷰 필수 |
| `envs/dev/main.tf` | 인프라 리드만 수정 |

### 4.4 시크릿 취급 — 전 팀 공통

| 항목 | 규칙 |
|---|---|
| 커밋 | 실제 값이 담긴 Secret 매니페스트 커밋 금지. `*.secret.example.yaml`만 커밋 |
| 전달 | 채팅·이슈·PR 본문에 붙여넣지 않는다 |
| 로그 | 비밀번호·JWT·Service Token·Tunnel Token을 로그에 출력하지 않는다 |
| 인증 API | 요청/응답 body 전체 로깅을 적용하지 않는다 |
| 식별자 입력 | ARN·도메인·토큰은 **렌더링된 텍스트를 복사하지 않는다.** §20.9 |

---

## §5. 기술 스택 및 버전 고정

**2026-08-10 기준 팩트체크 완료. 임의 변경 금지.**

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
| 노드 인스턴스 | `t3.medium` × 2 (min 1 / max 3) | 토이 규모 |
| RDS 인스턴스 | `db.t3.micro`, 20GB | 토이 규모 |

### 5.2 DynamoDB Lock Table을 쓰지 않는 이유

Terraform 1.10부터 S3 backend가 **native locking**을 지원한다. 별도 DynamoDB는 legacy이며, "S3 필수 옵션만 사용" 조건에 부합한다.

**S3 state 버킷 옵션 — 3개만:** Versioning / SSE-S3(AES256) / Public Access Block(4종). Object Lock·Replication·Lifecycle은 오버스펙.

### 5.3 애플리케이션 — ✅ v3.0 신설

| 항목 | 고정 버전 | 근거 |
|---|---|---|
| Java | **25** (LTS) | Spring Boot 4.x 1급 지원 |
| 컨테이너 JDK | **Amazon Corretto 25** | AWS 환경 정합 |
| Spring Boot | **4.1.0** | 2026-06-10 GA. 활성 지원 ~2027-07-31. **3.5는 2026-06-30 EOL** |
| Spring Framework | 7.x | Boot 4.1.0 BOM이 결정. 직접 지정 금지 |
| Spring Security | 7.x | Boot BOM |
| Gradle | **9.5.1** | 9.7.0은 2026-08-07 릴리스 — 채택하지 않는다 |
| JSON | **Jackson 3** | Boot 4 기본 |
| JWT | **Nimbus JOSE+JWT** (Boot BOM) | `jjwt` 계열 사용 금지 |
| MySQL 드라이버 | `com.mysql:mysql-connector-j` (Boot BOM) | 버전 직접 지정 금지 |
| 컨테이너 플랫폼 | **`linux/amd64`** | 노드가 x86_64. 미지정 시 `exec format error` |
| WAS/BFF 런타임 베이스 | `amazoncorretto:25-alpine` + **digest 핀** | |
| patient-web 베이스 | `nginxinc/nginx-unprivileged:stable-alpine` + **digest 핀** | **기본 리슨 포트 8080 · non-root** — §6.1과 정확히 일치 |
| cloudflared | `cloudflare/cloudflared` + **digest 핀** | `:latest` 금지 (§16-4) |

> 🔒 **베이스 이미지는 digest로 핀한다.** 태그는 움직이고, 움직인 사실은 장애로만 드러난다.
> ```powershell
> docker pull nginxinc/nginx-unprivileged:stable-alpine
> docker inspect --format='{{index .RepoDigests 0}}' nginxinc/nginx-unprivileged:stable-alpine
> ```
> 출력된 `name@sha256:...` 를 Dockerfile `FROM` 에 그대로 사용하고, 값은 §21에 기록한다.

### 5.4 버전 표의 유통기한

> **§5는 시간에 종속된다.** v1.0이 고정한 Kubernetes `1.33`은 작성 시점엔 옳았으나 apply 시점(2026-08)엔 확장 지원 구간이었다. 월 $73 → $438.
> **표를 믿되, apply/빌드 직전에 다시 확인한다.**

---

## §6. 표준 및 계약

### 6.1 컨테이너 표준 (EKS팀 전원 준수)

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

> ⚠️ `/readyz`를 하위 서비스 상태에 종속시키면 **장애가 상위로 전파**된다. BFF의 `/readyz`는 WAS를 확인하지 않는다.
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

### 6.3 리소스 명명 규칙

| 대상 | 규칙 | 예시 |
|---|---|---|
| AWS 리소스 | `hybrid-toy-<리소스>` | `hybrid-toy-eks` |
| ECR 리포지토리 | `hybrid-toy/<서비스>` | `hybrid-toy/bff` |
| K8s Deployment | `<서비스>` | `bff` |
| K8s Service | `<서비스>-svc` | `bff-svc` |
| K8s Secret | `<서비스>-secret` | `bff-secret` |
| K8s ConfigMap | `<서비스>-config` | `bff-config` |

### 6.4 공통 태그

```hcl
Project     = "hybrid-toy"
Environment = "dev"
ManagedBy   = "terraform"
```

---

### 6.5 애플리케이션 인증 계약 — ✅ v3.0 흡수

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

**환자 쿠키 / CSRF**

| 쿠키 | 속성 |
|---|---|
| `PATIENT_TOKEN` | HttpOnly ✅ / Secure ✅ / SameSite=Lax / Path=`/api/bff/patient` / Max-Age=1800 |
| `XSRF-TOKEN` | HttpOnly ❌ / Secure ✅ / SameSite=Lax / Path=`/api/bff/patient` |

- `XSRF-TOKEN`이 `HttpOnly=false`인 이유: Web이 값을 읽어 `X-XSRF-TOKEN` 헤더로 되보내야 한다.
- 환자 JWT를 응답 JSON·localStorage에 저장하지 않는다.
- CSRF 적용: `POST` / `PATCH` / `DELETE`. 직원 Bearer 경로는 대상 제외.
- 환자 흐름: `GET /auth/csrf` → 쿠키 수신 → register/login에 `X-XSRF-TOKEN` 헤더 → 성공 시 `PATIENT_TOKEN` 수신.

**역할 계약**

`PATIENT` / `DOCTOR` / `NURSE` / `ADMIN_STAFF` — 이 4종만 사용한다. (`RECEPTION`, `BILLING`, `ADMIN` 미사용)

| 역할 | 권한 |
|---|---|
| PATIENT | 본인의 예약·기록·처방전 |
| DOCTOR | 환자 목록 / 차트 조회 / 상병코드 조회 / **차트·처방 작성** |
| NURSE | 환자 목록 / 차트 조회 / 상병코드 조회 / 차트·처방 작성 **불가** |
| ADMIN_STAFF | 관리자 전용 API |

Spring Security 권한명: `ROLE_PATIENT` / `ROLE_DOCTOR` / `ROLE_NURSE` / `ROLE_ADMIN_STAFF`

> ✅ **v3.1** — 처방 발급은 차트 작성의 일부다. 별도 권한을 만들지 않는다. `NURSE`의 `POST /api/bff/staff/charts` 는 **403**이며, 처방 항목 포함 여부와 무관하다.

**계정 잠금 — 환자·직원 동일**

5회 연속 실패 → `failed_login_count=5`, `locked_until = now + 30분` → 잠금 중 요청 **423** → 30분 후 자동 해제 → 로그인 성공 시 카운트 0, `locked_until=NULL`. 관리자 수동 해제 API는 미구현.

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

**✅ v3.1 — 진료·처방 시나리오는 위 6개 경로만으로 성립한다. 신규 경로를 추가하지 않는다.**

경로를 늘리면 Ingress(§6.9)·BFF Security 정책(아래 표)·Cloudflare Access·cloudflared 검증을 전부 다시 돌려야 한다. 시나리오는 기존 경로에 **의미를 확정**하는 것으로 충족한다.

| 경로 | v3.1 확정 의미 | 권한 |
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
- 동일 `visit_no` 재요청은 **409 `duplicate_prescription`** (§6.7).
- `patient_id` 는 **본문에서 받지 않는다.** `visit_no` → `appointment` 조인으로 서버가 결정한다 (§6.6 위조 방어 4번 원칙).

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
| connect timeout | 2초 |
| read timeout | 5초 |
| 자동 Retry | **없음** (특히 인증 POST — 중복 가입·잠금 조기 발동) |
| WAS 400/401/404/409/423 | 계약된 상태·본문 그대로 전달 |
| WAS 500 / 연결 실패 / Timeout | **503 `upstream_unavailable`** 로 변환 |

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
| 409 | `duplicate_booking`, `slot_taken`, `patient_exists`, **`duplicate_prescription`** |
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
- OpenTelemetry·Zipkin은 이번 단계 미도입.

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

---

### 6.8 DB 계약 — ✅ v3.0 확정

**표기 차이 최종 판정** (DB팀 기존 스키마 ↔ 계약 v2)

| 항목 | 계약 v2 표기 | 확정 | 판단 |
|---|---|---|---|
| 환자 PK | `id` | **`patient_id`** | DB팀 현행 유지. API는 `actor_id`·`patient.id` 로 매핑 |
| 직원 PK | `id` | **`staff_id`** | 동일 |
| 직원 활성 | `active` | **`status ENUM('ACTIVE','INACTIVE','SUSPENDED')`** | 현행 유지. WAS가 `ACTIVE` 만 로그인 허용 |
| `must_change_password` | `DEFAULT false` | **`DEFAULT 0`** | ⚠️ 현행 `DEFAULT 1` → **0으로 변경** |
| `staff_user.role` | 4종 | **`ENUM('DOCTOR','NURSE','ADMIN_STAFF')`** | `PATIENT`는 `patient_user` 계층에서 부여. 정상 |
| 시간대 | Asia/Seoul | **Asia/Seoul, 전 컬럼 `DATETIME`** | JDBC `serverTimezone=Asia/Seoul` |

**필수 컬럼**

`patient_user`: `patient_id` / `login_id` UNIQUE / `password_hash` / `name` / `birth_date` / `failed_login_count` DEFAULT 0 / `locked_until` NULL / `created_at`

`staff_user`: `staff_id` / `login_id` UNIQUE / `password_hash` / `name` / `role` / `department` / `status` / `must_change_password` DEFAULT 0 / `failed_login_count` DEFAULT 0 / `locked_until` NULL / `created_at`

**규칙**

- 비밀번호는 **BCrypt 해시만** 저장. 평문 컬럼 없음.
- 환자는 API로 가입한다. **직원 셀프 가입 없음** — seed SQL로 생성.
- 테스트 직원 계정은 `must_change_password = 0`.
- 예약 동시성은 **DB UNIQUE 제약**으로 최종 방어한다 (`slot_taken` 판정 근거).
- 앱은 `app_was` 계정만 사용한다. `admin`은 계정 생성·스키마 변경 전용.

**예약 상태 매핑**

DB 원본값 → **WAS 표준 enum** 변환 매퍼는 1개만 유지한다. 화면별 한글 라벨은 각 Web이 처리한다.

```
DB: booked  →  API: BOOKED  →  환자 화면 "예약" / 직원 화면 "대기"
```

WAS는 DB 원본값도, 한글 라벨도 반환하지 않는다.

---

**진료·처방 테이블 — ✅ v3.1 신설**

기존 5개 테이블(`patient_user`, `staff_user`, `doctor`, `appointment`, 그리고 계정 부속)에 **5종을 추가한다.** 기존 테이블의 컬럼은 변경하지 않는다.

| 테이블 | 행수(예상) | 역할 |
|---|---|---|
| `icd_code` | **14,283** | KCD 상병코드 마스터. `code` PK |
| `icd_code_synonym` | **37,543** | 검색용 동의어 색인. `code` FK, N:1 |
| `chart` | 진료마다 1 | 예약 1건당 차트 1건 |
| `prescription` | 차트마다 0~1 | 차트 1건당 처방 최대 1건 |
| `prescription_item` | 처방마다 1~N | 약품 항목 |

**`icd_code` — 필수 컬럼**

`code` VARCHAR(6) PK / `name_kr` VARCHAR(200) NOT NULL / `name_en` VARCHAR(255) NULL / `gender_restriction` CHAR(1) NULL / `age_min` **INT** NULL / `age_max` **INT** NULL / `infectious_class` VARCHAR(8) NULL / `oriental_medicine` VARCHAR(16) NULL

**`icd_code_synonym` — 필수 컬럼**

`synonym_id` BIGINT PK AUTO_INCREMENT / `code` VARCHAR(6) NOT NULL FK→`icd_code.code` / `name_kr` VARCHAR(200) NOT NULL / `name_en` VARCHAR(255) NULL

> ⚠️ **`code`는 원본에서 유일하지 않다.** `E1140` 한 코드에 명칭 레코드가 **60건** 존재한다(동의어). 마스터 1행 + 동의어 N행으로 분리하지 않으면 PK 제약 위반으로 적재가 실패한다. 상세 근거는 §6.10.

**필수 인덱스** — 없으면 37,543행 풀스캔이 매 타건마다 발생한다

```sql
INDEX idx_icd_syn_code   ON icd_code_synonym (code)
INDEX idx_icd_syn_name   ON icd_code_synonym (name_kr(32))
INDEX idx_icd_code_name  ON icd_code (name_kr(32))
```

**`chart` — 필수 컬럼**

`chart_id` BIGINT PK / `visit_no` VARCHAR(32) **UNIQUE** FK→`appointment.visit_no` / `patient_id` BIGINT NOT NULL / `doctor_staff_id` BIGINT NOT NULL FK→`staff_user.staff_id` / `icd_code` VARCHAR(6) NOT NULL FK→`icd_code.code` / `icd_name_snapshot` VARCHAR(200) NOT NULL / `chief_complaint` VARCHAR(500) NULL / `note` TEXT NULL / `created_at` DATETIME NOT NULL

**`prescription` — 필수 컬럼**

`prescription_id` BIGINT PK / `chart_id` BIGINT **UNIQUE** FK→`chart.chart_id` / `patient_id` BIGINT NOT NULL / `issued_by_staff_id` BIGINT NOT NULL / `issued_at` DATETIME NOT NULL

**`prescription_item` — 필수 컬럼**

`item_id` BIGINT PK / `prescription_id` BIGINT NOT NULL FK / `drug_name` VARCHAR(200) NOT NULL / `dosage` VARCHAR(50) NOT NULL / `frequency` VARCHAR(50) NOT NULL / `duration_days` **INT** NOT NULL / `line_no` **INT** NOT NULL

**✅ v3.1 — 숫자 컬럼은 `INT` 로 통일한다. `TINYINT` / `SMALLINT` 를 쓰지 않는다.**

Hibernate 는 Java 타입에서 JDBC 타입 코드를 정하고 `ddl-auto: validate` 가 이를 실제 컬럼과 대조한다.

| Java | JDBC | MySQL |
|---|---|---|
| `int` / `Integer` | INTEGER | `INT` |
| `short` / `Short` | SMALLINT | `SMALLINT` |
| `byte` / `Byte` | TINYINT | `TINYINT` |

카운터·일수·연령을 `TINYINT`/`SMALLINT` 로 두면 엔티티를 `byte`/`short` 로 낮춰야 하고, `UNSIGNED`(0~255)가 Java `byte`(-128~127)를 넘어 **조용한 오버플로**가 생긴다. 저장 공간 차이는 이 규모에서 무의미하다.

적용 컬럼: `patient_user.failed_login_count` · `staff_user.failed_login_count` · `icd_code.age_min` · `icd_code.age_max` · `prescription_item.duration_days` · `prescription_item.line_no`

**규칙**

- `chart.visit_no` **UNIQUE**가 처방 중복 발급의 최종 방어선이다 (`duplicate_prescription` 판정 근거). 예약 동시성과 동일한 원칙 — **애플리케이션 체크는 보조, DB 제약이 본선.**
- `chart.icd_name_snapshot` — 상병코드 명칭은 KCD 개정 시 바뀐다. **발급 시점 명칭을 복사 보관한다.** 과거 처방전이 소급 변경되면 의료 기록으로서 무효다.
- `prescription.patient_id` 는 `chart` 에서 파생한다. 요청 본문 값을 신뢰하지 않는다.
- `icd_code` / `icd_code_synonym` 은 **참조 마스터**다. WAS는 `SELECT` 만 수행한다. `app_was` 계정에 이 두 테이블의 `INSERT`·`UPDATE`·`DELETE` 를 부여하지 않는다 (§12.3 GRANT 반영).
- 처방 항목 약품명은 이번 단계에서 **자유 텍스트**다. 의약품 표준코드 연동은 백로그(§17.3).

---

### 6.9 외부 ALB Ingress 경로 계약 — ✅ v3.0 교정

```
/api/bff/patient  →  bff-svc:8080
/                 →  patient-web-svc:8080     ← 반드시 마지막
```

**금지 규칙**

| 금지 | 이유 |
|---|---|
| `/api` → bff-svc | 범위가 과하다 |
| `/api/bff/staff` → bff-svc | 직원 API의 외부 노출 |
| `/` 를 먼저 선언 | Prefix 매칭이 `/`에서 전부 흡수된다 |

- `patient-web`은 `/api/bff/staff/**`를 프록시하지 않고 **404**를 반환한다.
- 환자 Web과 API가 동일 도메인이므로 이번 단계에서는 **CORS 구성을 추가하지 않는다.**

---

### 6.10 공공데이터(KCD 상병코드) 적재 계약 — ✅ v3.1 신설

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

**적재 필터 — A안 확정**

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

**대표명 선정 규칙**

동일 `상병기호`의 첫 등장 레코드를 `icd_code.name_kr` / `name_en` 으로 삼는다. 원본은 KCD 공표 순서를 유지하므로 첫 행이 공식 분류명이다. 나머지 전 행(대표명 포함)은 `icd_code_synonym` 에 적재한다 — 검색은 동의어 테이블만 조회하면 되므로 UNION 이 불필요해진다.

**컬럼 매핑**

| 원본 | 대상 | 변환 |
|---|---|---|
| `상병기호` | `code` | 그대로 |
| `한글명` | `name_kr` | 그대로 |
| `영문명` | `name_en` | 빈 문자열 → `NULL` |
| `성별구분` | `gender_restriction` | 빈 문자열 → `NULL` |
| `상한연령` / `하한연령` | `age_max` / `age_min` | 빈 문자열 → `NULL`, 그 외 `TINYINT` |
| `법정감염병구분` | `infectious_class` | 빈 문자열 → `NULL` (보유 코드 486종) |
| `양한방구분` | `oriental_medicine` | 그대로 (한방 전용 151종) |
| `완전코드구분` / `주상병사용구분` | — | **적재하지 않는다.** 필터에만 사용 |

**SQL 생성 규칙 (`convert-icd.ps1`)** — ⚠️ 초안에서 2건 교정됨

- 출력 인코딩 **UTF-8 (BOM 없음)**. BOM이 붙으면 MySQL 클라이언트가 첫 구문을 깨뜨린다.
- `INSERT ... VALUES` **1,000행 배치**. 단건 INSERT 37,543회는 수 분이 걸린다.
- 파일 선두에 `SET NAMES utf8mb4;` / `SET autocommit=0;`, 말미에 `COMMIT;`
- 작은따옴표는 `''` 로 이스케이프한다. 실측 5건 존재. 백슬래시는 0건이나 방어적으로 처리한다.

**교정 1 — `DELETE FROM icd_code` 를 쓰지 않는다**

초안은 재실행 안전성을 위해 선행 `DELETE` 를 지시했다. **차트가 생기는 순간 실패한다.**

```
DELETE FROM icd_code;
→ ERROR 1451: Cannot delete or update a parent row:
  a foreign key constraint fails (`chart`, CONSTRAINT `fk_chart_icd` ...)
```

`chart.icd_code` 가 `ON DELETE RESTRICT` 로 마스터를 참조하기 때문이다. 확정 방식:

| 테이블 | 방식 | 이유 |
|---|---|---|
| `icd_code_synonym` | `TRUNCATE` 후 전량 재적재 | 참조하는 테이블이 없다. 자식 테이블은 TRUNCATE 가능 |
| `icd_code` | **UPSERT** (`INSERT ... AS new ON DUPLICATE KEY UPDATE`) | 진료 기록을 보존하면서 명칭만 갱신 |

- 구문은 **`AS new` 별칭 형식**을 쓴다. 구형 `VALUES(col)` 은 MySQL 8.0.20+ 에서 deprecated 경고를 낸다. **최소 요구 버전: MySQL 8.0.19**
- 실측 확인: 차트가 `E1140` 을 참조 중인 상태에서 재적재 → 마스터 명칭은 갱신되고 `chart.icd_name_snapshot` 은 **발급 시점 값을 유지**한다. §6.8 스냅샷 설계가 의도대로 동작한다.

**교정 2 — `ANALYZE TABLE` 을 반드시 실행한다**

대량 적재 직후 InnoDB 의 행수 추정치는 실제와 크게 다르다. 실측값:

| 시점 | `icd_code` 추정 | `icd_code_synonym` 추정 |
|---|---|---|
| 적재 직후 | **3** | **2** |
| `ANALYZE TABLE` 후 | 14,433 | 37,883 (근사치. 정상) |

추정치가 3행이면 옵티마이저가 인덱스를 버리고 풀스캔을 고른다. seed 파일 말미에 `ANALYZE TABLE icd_code, icd_code_synonym;` 을 포함한다.

**검증 (게이트 D2 — §12)**

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

부분일치는 인덱스를 타지 않지만 **이 규모에서는 10ms 미만**이다. 이번 단계에서 FULLTEXT 는 불필요하다. 데이터가 수십만 건으로 늘거나 동시 사용자가 증가하면 그때 전환한다(§17.3).

**갱신 정책** — KCD는 연 1~2회 개정된다. 개정 시 `data.json` 교체 → 스크립트 재실행 → `04_icd_seed.sql` 재커밋 → 재적재. **자동 동기화는 백로그(§17.3)다.** 기존 `chart.icd_name_snapshot` 은 갱신하지 않는다.

---

## §7. 설계상 핵심 판단

### 7.1 ALB를 Terraform으로 만들지 않는다
LBC가 Ingress를 감지해 ALB를 동적 생성하는 것이 EKS 표준이다. Terraform으로 만들면 Target Group을 수동 관리해야 하고 파드 IP 변경마다 드리프트가 난다.
**Terraform 범위:** IRSA 권한 + ACM 인증서. **EKS팀 범위:** Ingress 작성 → ALB 생성.

### 7.2 ECR을 `-target`으로 선행 apply 한다
ECR은 의존성이 없다. 먼저 만들면 EKS팀이 클러스터 생성을 기다리지 않고 빌드·푸시를 시작한다. `-target`은 평시 안티패턴이나 **팀 언블로킹 용도는 정당하다.** 직후 전체 apply로 정합화한다.

### 7.3 `create_database_subnet_group = false`
`modules/rds`에 이미 `aws_db_subnet_group`이 있다. 둘 다 켜면 중복 리소스가 생긴다. **DB 리소스는 DB팀 디렉토리에 모은다.**
> ⚠️ `create_database_subnet_route_table`은 **`true`** 다. 두 인자는 역할이 다르다.

### 7.4 `single_nat_gateway = true`
NAT는 시간당 + 데이터 처리 과금이다. **대가:** AZ 장애 시 해당 NAT를 쓰는 파드 전체의 아웃바운드가 끊긴다(SPOF).

### 7.5 `image_tag_mutability = "IMMUTABLE"`
동일 태그 재푸시를 차단한다. **대가:** `:latest` 푸시 실패. git SHA 태그를 강제한다.

### 7.6 EKS 엔드포인트 public + private 병행
팀원이 각자 PC에서 `kubectl`을 써야 한다. **대가:** API 서버가 인터넷에 노출된다. IAM 인증이 걸려 있으나 운영 전환 시 private 전용 + CIDR 제한 필수.

### 7.7 `skip_final_snapshot = true`
destroy가 스냅샷 대기로 막히는 것을 방지한다. **대가:** 데이터 완전 소실. **DB팀은 DDL·seed를 반드시 git에 커밋한다.**

### 7.8 cloudflared를 BFF 담당이 맡는다
cloudflared는 `bff-svc`를 직접 호출한다. 호출 대상을 아는 사람이 배포하는 것이 경계상 자연스럽다.

### 7.9 BFF `/readyz`를 WAS에 종속시키지 않는다 — ✅ v3.0 신설
BFF의 준비 상태를 WAS 상태로 판정하면 WAS 일시 장애가 BFF Pod 전량 NotReady → ALB Target 전량 제거 → **부분 장애가 전면 장애로 승격**된다. WAS 장애는 `503 upstream_unavailable` 응답으로 표현한다.

### 7.10 Cloudflare Access JWT를 BFF가 검사하지 않는다 — ✅ v3.0 신설
`Cf-Access-Jwt-Assertion` 헤더의 **존재 여부만** 확인하는 것은 보안이 아니다(위조 가능). Access JWT 검증은 대시보드의 **Protect with Access** 설정으로 cloudflared가 수행한다. BFF는 **직원 애플리케이션 JWT와 role**을 검증한다.

### 7.11 WAS가 런타임에 공공데이터포털을 호출하지 않는다 — ✅ v3.1 신설

"WAS가 공공데이터포털에서 API를 받아와 DB에 저장한다"는 요구를 **런타임 호출로 구현하지 않는다.** 오프라인 seed로 대체한다(§6.10).

| 런타임 호출 시 발생하는 문제 | 근거 |
|---|---|
| 아웃바운드가 **단일 NAT** 를 경유한다 | §7.4 — AZ 장애 시 진료 코드 조회 전체 중단. 인프라 SPOF가 **진료 기능 SPOF로 승격**된다 |
| WAS `/readyz` 의 의미가 흐려진다 | §6.1 — `/readyz` 는 **DB 커넥션만** 판정한다. 외부 API를 여기 얹으면 §7.9와 같은 종속 전파가 재발한다 |
| 시크릿이 6종 → 7종으로 늘어난다 | 구축설명서 §3.1 — 서비스키 발급·전달·회전이 전부 사람 작업이다 |
| 대상 데이터가 **정적 마스터**다 | KCD는 연 1~2회 개정. 47,798행을 요청마다 프록시할 근거가 없다 |
| 외부 API 응답시간이 BFF 5초 read timeout 안에 들어온다는 보장이 없다 | §6.6 — 초과 시 `503 upstream_unavailable`. 장애 원인이 외부로 이동해 진단이 어려워진다 |

**시연 요건으로 실시간 수집을 보여야 한다면**, WAS가 아니라 **일회성 Kubernetes Job(`icd-loader`)** 으로 분리한다. Job은 `app` 네임스페이스에서 1회 실행 후 종료하며, WAS는 그 존재를 알지 못한다. Job 실패가 WAS 기동·헬스체크에 영향을 주지 않는 것이 유일한 허용 조건이다. **이번 단계에서는 채택하지 않는다** (§17.3 백로그).

### 7.12 처방 발급에 신규 API 경로를 만들지 않는다 — ✅ v3.1 신설

`POST /api/bff/staff/prescriptions` 를 신설하면 다음이 전부 재검증 대상이 된다 — BFF Security 정책 표(§6.6), 역할별 권한 매핑, Cloudflare Access 경유 동작, G3 체크리스트. 얻는 것은 URL의 의미적 선명함뿐이다.

**차트와 처방은 같은 진료 행위의 두 면이다.** 차트 없는 처방은 의료 기록으로 성립하지 않으므로 두 리소스의 생명주기는 애초에 분리되지 않는다. `POST /api/bff/staff/charts` 단일 트랜잭션이 도메인적으로도 옳다.

**대가:** 처방만 수정하는 API가 없다. 수정·취소가 필요해지면 그때 경로를 추가한다 — 뼈대 완성 후다(§0.3).

---

## §8. apply 전 필수 선조치 (완료)

> ✅ 전 항목 완료. 재적용 시 재확인 대상으로 남긴다.

### 8.1 EKS 접근 권한 부여
`enable_cluster_creator_admin_permissions = true`는 apply 실행자 1명만 관리자로 등록한다. 나머지 팀원은 `kubectl` 자체가 동작하지 않는다.

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
# envs/dev/main.tf — module "eks" 블록 안
developer_iam_arns = {
  web = "arn:aws:iam::597106152264:user/kusweb"
  bff = "arn:aws:iam::597106152264:user/kusbff"
  was = "arn:aws:iam::597106152264:user/kuswas"
  db  = "arn:aws:iam::597106152264:user/kusdb"
}
```

> `principal_arn`에 **IAM Group ARN은 쓸 수 없다.** 개별 User ARN 필수.
> IAM 정책과 `access_entries`는 **별개다.** 전자는 AWS API 호출 권한(`update-kubeconfig`), 후자는 클러스터 내 RBAC. **둘 다 있어야 G1 통과.**

### 8.2 S3 버킷명 확정
`hybrid-toy-tfstate-kuspital`. `backend-bootstrap/variables.tf`와 `envs/dev/backend.tf` 값이 다르면 `init`에서 즉시 실패한다.

### 8.3 ECR 태그 정책
`IMMUTABLE` 확정. `:latest` 재푸시가 실패한다. 생성 후 변경하려면 리포지토리 재생성이 필요하다.

### 8.4 DB 보안
TLS 강제 + Secrets Manager 전환 — 둘 다 apply 전 적용 완료. §13 참조.

---

## §9. 전체 실행 순서 및 게이트

### 9.1 페이즈 구조

| 페이즈 | 내용 | 상태 | 게이트 |
|---|---|---|---|
| **P0** | AWS 불필요 작업 — 전 팀 병렬 | ✅ 완료 | — |
| **P1** | 인프라 리드 단독 apply | ✅ 완료 | **G1** ✅ 2026-08-10 |
| **P2** | 3팀 병렬 개발 + 배포 | ▶ 진행 중 | **G2**: 흐름1 완성 |
| **P3** | 흐름2(내부 터널) 연결 | 대기 | **G3**: 전체 완료 |

### 9.2 의존 관계도

```
                  ┌─→ ECR ─────────────────────────────┐
인프라 apply ─G1─┤                                      ├─→ 이미지 빌드/푸시 (전원 즉시 병렬)
                  └─→ EKS / RDS                         ┘
                        │
              DB 스키마 ─┴─→ WAS ─→ BFF ─→ Web ─→ Ingress ─G2─→ 흐름1 완료
                                      └─→ cloudflared ────G3─→ 흐름2 완료
```

### 9.3 임계 경로

**`DB → WAS → BFF → Web`이 임계 경로다.**

- 이미지 빌드·푸시는 4명 전원 **즉시 병렬** 가능하다. **배포 순서만 직렬이다.**
- 하위 서비스가 없으면 상위가 헬스체크에 실패해 무한 재시작한다.
- WAS 담당은 **스키마 대기로 멈추지 말 것.** 커넥션 수립만 확인되면 다음으로 넘어간다.

### 9.4 게이트 통과 조건

| 게이트 | 조건 | 상태 |
|---|---|---|
| **G1** | `terraform output` 전체 공유 + 전 팀원 `kubectl get nodes` 성공 | ✅ 2026-08-10 |
| **D1** | `app_was` 자격으로 `SELECT 1` + `Ssl_cipher` 비어 있지 않음 | ✅ 2026-08-12 |
| **D2** | `icd_code` 14,283 / `icd_code_synonym` 37,543 + `app_was` 읽기 전용 | ✅ 2026-08-12 (RDS) |
| **W1** ✅v3.2 | WAS `gradlew build` — 컨텍스트 기동 + `@Query` JPQL 전량 파싱 | ✅ |
| **D3** ✅v3.2 | WAS `/readyz` → `db:up` = **`ddl-auto: validate` 통과** | ✅ |
| **W2** ✅v3.2 | `verify-was.ps1` **38/38** | ✅ |
| **B1** ✅v3.2 | BFF `/readyz` → `{"status":"ok"}` (WAS 미의존) | ✅ |
| **B2** ✅v3.2 | `verify-bff.ps1` **45/45** | ✅ |
| **G2** | `verify-flow1.ps1` **24/24** + **브라우저 실동작 7단계** | ✅ 2026-08-12 |
| **G3** | `verify-flow2.ps1` **29/29** — Access Service Auth · Tunnel · 직원 3역할 · **DOCTOR 처방 201 / NURSE 403** | ✅ 2026-08-13 |

> ✅ **프로젝트 뼈대(G1 → G3) 완성.** OKD Web 은 프로젝트 기간 제약으로 범위 밖으로
> 이관했다. §17.3 백로그(NetworkPolicy·mTLS·CI/CD·HPA·관측성 등)는 착수하지 않는다.
> 상세 기록은 §22.8.
>
> 🚨 **G2 는 스크립트만으로 닫히지 않는다.**
> `verify-bff.ps1` 45개와 `verify-flow1.ps1` 22개를 전부 통과한 상태에서
> **브라우저 회원가입이 403 으로 실패했다.** PowerShell `CookieContainer` 는
> 조회 시 경로를 인자로 받지만, 브라우저 `document.cookie` 는 현재 문서
> 경로에 해당하는 쿠키만 반환한다. 하네스가 브라우저보다 관대했다.
> **사람이 브라우저로 직접 통과하는 것이 G2 의 최종 조건이다.**

> ✅ **v3.1** — **D2는 WAS를 막지 않는다.** WAS 담당은 D1(커넥션)만 통과하면 착수한다. D2는 `GET /staff/icd-codes` 통합 검증 시점까지만 완료되면 된다. 임계 경로(§9.3)는 변하지 않는다.

---

## §10. 인프라 리드팀 실행 절차

### P0 ~ P1 — ✅ 완료 (기록은 §19, §20)

### P2 — 지원 및 Cloudflare 외부 구성

| # | 작업 | 비고 |
|---|---|---|
| 1 | `JWT_SIGNING_KEY` 생성 → BFF 담당에게 전달 | `openssl rand -base64 48` (또는 PowerShell `[Convert]::ToBase64String((1..48\|%{Get-Random -Max 256}))`) |
| 2 | RDS 마스터 시크릿 값 → DB팀 전달 경로 확인 | §19.5 |
| 3 | EKS팀 Ingress 이슈 대응 | Target Group unhealthy 등 |
| 4 | Cloudflare **SSL/TLS = Full (strict)** | Flexible이면 무한 리다이렉트 루프 |
| 5 | Web 담당에게 ALB DNS명 수령 → `www` CNAME 등록 (**🟠 주황 구름 ON**) | |
| 6 | WAF Managed Ruleset 활성화 | |
| 7 | Rate Limiting Rule 구성 | |
| 8 | Bot Fight Mode 활성화 | |

### P3 — 내부 흐름 구성

| # | 작업 | 산출물 → 전달 |
|---|---|---|
| 1 | Zero Trust → Networks → Tunnels → **Tunnel 생성** | Tunnel Token → BFF 담당 |
| 2 | Public Hostname: `staff-api.kuspitalsoldeskproject.org` → `http://bff-svc.app.svc.cluster.local:8080` | — |
| 3 | Zero Trust → Access → **Application 생성** (위 도메인) | — |
| 4 | Access Policy — **Action = `Service Auth`** | — |
| 5 | **Service Token 발급** | Client ID + Secret → OKD팀 |
| 6 | Tunnel 설정에서 **Protect with Access 활성화 + 올바른 AUD 선택** | — |

> 🚨 **Access Policy의 Action은 반드시 `Service Auth`.** `Allow`로 두면 Service Token을 보내도 IdP 로그인을 요구해 OKD Pod가 HTML을 받는다.
> 🚨 **`staff-api` DNS 레코드를 미리 만들지 않는다.** Tunnel Public Hostname 등록 시 자동 생성되며, 수동 레코드가 있으면 충돌한다.

---

## §11. EKS팀 실행 절차

### 11.0 3인 공통 규칙

| 항목 | 규칙 |
|---|---|
| 네임스페이스 | 전부 `app` |
| 컨테이너 포트 | 8080 |
| 헬스체크 | `/healthz`, `/readyz` (의미는 §6.1) |
| 이미지 태그 | git short SHA. **`:latest` 금지** |
| 베이스 이미지 | **digest 핀** (§5.3) |
| 하위 서비스 주소 | ConfigMap 주입. 하드코딩 금지 |
| 매니페스트 | `k8s/<서비스>/` 에 커밋 |
| 실제 Secret | **커밋 금지.** `*.secret.example.yaml`만 |

### 11.1 공통 P0 — 클러스터 없이 가능

| # | 작업 |
|---|---|
| 1 | Dockerfile 작성 + 로컬 빌드 성공 |
| 2 | `/healthz`, `/readyz` 구현 |
| 3 | `docker compose`로 web→bff→was→mysql 로컬 통합 확인 |
| 4 | `k8s/` 매니페스트 작성 |
| 5 | 환경변수를 §6.2 계약대로 읽도록 구현 |

### 11.2 공통 — 이미지 빌드·푸시 (전원 즉시 병렬)

```powershell
$ACCOUNT  = "597106152264"
$REGION   = "ap-northeast-2"
$REGISTRY = "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
$SVC      = "was"                       # was | bff | patient-web
$TAG      = (git rev-parse --short HEAD)

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY
docker build --platform linux/amd64 -t "$REGISTRY/hybrid-toy/$SVC`:$TAG" .
docker push "$REGISTRY/hybrid-toy/$SVC`:$TAG"
```

> ⚠️ PowerShell에서 `:`는 변수명 구분자로 해석될 수 있다. `` `: `` 로 이스케이프하거나 `${SVC}` 형태를 쓴다.
> ⚠️ `--platform linux/amd64` 미지정 시 ARM 이미지가 푸시되어 파드가 `exec format error`로 크래시한다.

### 11.3 담당별 P2 — 의존 역순으로 배포

> **배포 순서: `WAS → BFF → Web`.**

#### ① WAS 담당 — 최우선

| 순서 | 작업 | 검증 |
|---|---|---|
| 1 | `was-secret` 생성 (DB_USER / DB_PASSWORD) | `kubectl -n app get secret was-secret` |
| 2 | `was-config` ConfigMap 생성 | `kubectl -n app get cm was-config` |
| 3 | Deployment + Service(ClusterIP 8080) 배포 | `kubectl -n app get pod -l app=was` Running |
| 4 | DB 커넥션 기동 확인 | 파드 로그 |
| 5 | 헬스체크 확인 | 아래 |

```bash
kubectl -n app run tmp --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s http://was-svc.app.svc.cluster.local:8080/readyz
```

```powershell
kubectl -n app create secret generic was-secret `
  --from-literal=DB_USER=app_was --from-literal=DB_PASSWORD='<DB팀 발급>'
```

#### ② BFF 담당 — WAS Service 생성 후

| 순서 | 작업 | 검증 |
|---|---|---|
| 1 | `bff-secret` 생성 (`JWT_SIGNING_KEY`) | `kubectl -n app get secret bff-secret` |
| 2 | `bff-config` ConfigMap 생성 (§6.2의 5개 값) | `kubectl -n app get cm bff-config` |
| 3 | Deployment + Service 배포 | Pod Running |
| 4 | BFF → WAS 호출 검증 | 임시 파드 curl |
| 5 | **[P3]** cloudflared 배포 | 아래 |

**P3 — cloudflared 배포** (Tunnel Token 수령 후)

```powershell
kubectl -n app create secret generic cloudflared-secret --from-literal=TUNNEL_TOKEN='<리드 발급>'
```

```yaml
# k8s/cloudflared/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: app
spec:
  replicas: 2                     # 터널 이중화. 1개면 재시작 중 내부 흐름 단절
  selector:
    matchLabels: { app: cloudflared }
  template:
    metadata:
      labels: { app: cloudflared }
    spec:
      containers:
        - name: cloudflared
          # ✅ v3.0 — :latest 금지. digest 핀 (§5.3 / §21)
          image: cloudflare/cloudflared@sha256:<DIGEST>
          args: ["tunnel", "--no-autoupdate", "run"]
          env:
            - name: TUNNEL_TOKEN
              valueFrom:
                secretKeyRef: { name: cloudflared-secret, key: TUNNEL_TOKEN }
          resources:
            requests: { cpu: "50m",  memory: "64Mi" }
            limits:   { cpu: "200m", memory: "256Mi" }
```

> cloudflared는 **아웃바운드 연결만** 한다. Service·Ingress·인바운드 SG 규칙 전부 불필요하다.
> 검증: `kubectl -n app logs deploy/cloudflared` → 등록 성공 + 대시보드 Tunnel **HEALTHY**

#### ③ Web 담당 — BFF Service 생성 후

| 순서 | 작업 | 검증 |
|---|---|---|
| 1 | `patient-web-config` ConfigMap 주입 | — |
| 2 | Deployment + Service 배포 | Pod Running |
| 3 | `/api/bff/staff/**` 가 404인지 확인 | nginx.conf 검토 + curl |
| 4 | **Ingress 작성 — ALB 실제 생성 지점** | 아래 |
| 5 | ALB DNS명 확보 → 리드에게 전달 | `kubectl -n app get ingress` |

```yaml
# k8s/ingress/patient-web-ingress.yaml   ✅ v3.0 — 2-path 확정본
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

> 🚨 **`/api/bff/staff` 규칙을 추가하지 않는다.** 직원 API의 외부 노출은 설계 위반이다.
> 🚨 **ACM ARN 절단 사고 3회차 후보.** 적용 직후 반드시 대조한다.
> ```powershell
> kubectl -n app get ingress patient-web -o jsonpath="{.metadata.annotations}"
> ```

```bash
kubectl -n app get ingress patient-web -w   # ADDRESS에 ALB DNS가 뜰 때까지 (~3분)
```

이후 리드가 Cloudflare DNS에 CNAME 등록(🟠 주황) → **🚩 G2**

---

## §12. DB팀 실행 절차

### 12.1 접속 경로 — 로컬 PC 직접 접속 불가

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

### 12.2 실행 순서

| 페이즈 | 작업 |
|---|---|
| P0 | ERD 설계 |
| P0 | DDL / GRANT / SEED 작성 → **git 커밋 필수** (§7.7) |
| P0 | 로컬 MySQL 8.0에서 문법 검증 |
| P0 | 직원 BCrypt 해시 생성 |
| P2 | 임시 파드 접속 성공 확인 |
| P2 | `commondb` 생성 → DDL 실행 → **즉시 WAS 담당에게 통보** |
| P2 | `app_was` 계정 생성 → WAS 담당에게 전달 |
| P2 | seed 투입 (`03_seed.sql`) |
| P2 | **`04_icd_seed.sql` 투입 → 게이트 D2 검증** ✅ v3.1 |
| P2 | 인덱스 검증 (`EXPLAIN`) |

### 12.3 앱 전용 계정 — `admin` 공유 금지

> ⚠️ **v3.1 교정** — 초안은 `GRANT ... ON commondb.*` 후 ICD 테이블만 `REVOKE` 하는 방식이었다.
> **MySQL 에서 동작하지 않는다.** DB 단위로 부여한 권한은 테이블 단위로 회수할 수 없다:
> ```
> ERROR 1147 (42000): There is no such grant defined for user 'app_was' on host '%' on table 'icd_code'
> ```
> `partial_revokes=ON` 을 켜도 동일하다 (이 변수는 전역→DB 범위 전용). 실측 확인했다.
> **테이블 단위 명시 부여**로 전환한다. 화이트리스트가 되므로 보안상으로도 낫다.

```sql
CREATE USER IF NOT EXISTS 'app_was'@'%' IDENTIFIED BY '<강력한 비밀번호>';
ALTER  USER 'app_was'@'%' REQUIRE SSL;   -- §13.2 TLS 강제와 정합. 필수

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

-- 상병코드 마스터 — 읽기 전용 ✅ v3.1
GRANT SELECT ON commondb.icd_code         TO 'app_was'@'%';
GRANT SELECT ON commondb.icd_code_synonym TO 'app_was'@'%';

FLUSH PRIVILEGES;
```

- `DROP` / `ALTER` / `CREATE` 권한은 주지 않는다. 스키마 변경은 DB팀 전담.
- `REQUIRE SSL` 누락 시 TLS 강제 환경에서 동작은 하나 이중 방어가 성립하지 않는다.
- ✅ **v3.1** — ICD 마스터를 읽기 전용으로 두는 것이 §7.11 "런타임 적재 금지"의 **권한 차원 강제**다. 코드 리뷰에만 의존하지 않는다.
- ⚠️ **테이블을 새로 추가하면 이 목록에 GRANT 를 반드시 추가한다.** 누락 시 `SELECT command denied to user 'app_was'` 가 발생한다. 이것이 명시 부여 방식의 유일한 대가다.

**검증**

```sql
SHOW GRANTS FOR 'app_was'@'%';
-- USAGE 줄에 REQUIRE SSL / icd_* 는 SELECT 만 / commondb.* 광역 줄 없음
```

> ⚠️ `GRANT ... ON commondb.*` 줄이 남아 있으면 이전 실행의 잔재다.
> `REVOKE ALL PRIVILEGES ON commondb.* FROM 'app_was'@'%';` 로 회수한 뒤 위를 다시 실행한다.

---

## §13. 보안 및 암호화 기준

### 13.1 저장 암호화 (at-rest) — ✅ 적용

`storage_encrypted = true`, AWS 관리형 키(`aws/rds`). 스냅샷·백업·Read Replica가 암호화를 상속한다.

**CMK 전환 — 미적용 (백로그).** 토이 규모에는 오버스펙이며, KMS 키 삭제 대기가 최소 7일이라 destroy 후 재생성 시 alias 충돌이 발생한다.

> ⏱️ `storage_encrypted`와 `kms_key_id`는 **기존 인스턴스에서 변경 불가**하다. 스냅샷 → 암호화 복사 → 복원 경로를 타야 한다.

### 13.2 전송 암호화 (in-transit / TLS) — ✅ 적용

```hcl
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.project_name}-rds-"
  family      = "mysql8.0"

  parameter {
    name  = "require_secure_transport"
    value = "1"        # ✅ v3.0 — AWS가 ON을 1로 정규화한다. 상시 drift 제거 (§20.5)
  }

  lifecycle { create_before_destroy = true }
  tags = var.common_tags
}
```

**🚨 WAS JDBC URL — v3.0 교정**

```
jdbc:mysql://<endpoint>:3306/commondb?sslMode=REQUIRED&serverTimezone=Asia/Seoul&characterEncoding=UTF-8
```

| 항목 | 판정 |
|---|---|
| `useSSL=true&requireSSL=true` | ❌ **사용 금지.** Connector/J 8.0.13+ 에서 deprecated. 조합에 따라 무시되거나 경고만 남는다 |
| `sslMode=REQUIRED` | ✅ **채택.** 암호화는 강제하되 서버 인증서 체인은 검증하지 않는다 |
| `sslMode=VERIFY_CA` | 백로그. RDS CA 번들을 이미지에 넣고 `trustCertificateKeyStoreUrl` 지정 필요 — 뼈대 단계에서는 과하다 |

> ⚠️ TLS 옵션 누락 시 커넥션 **100% 실패**한다.

### 13.3 마스터 비밀번호 — ✅ Secrets Manager 전환 완료

```hcl
# password = var.db_password        <- 제거됨 (배타적 인자)
manage_master_user_password = true
```

> `password`와 `manage_master_user_password`는 **동시 지정 불가**하다.

### 13.4 적용된 보안 통제

| 항목 | 상태 |
|---|---|
| RDS `publicly_accessible = false` | ✅ |
| RDS SG — EKS 노드 SG 출처만 허용 | ✅ |
| DB 서브넷 전용 RT, NAT 라우트 없음 | ✅ |
| DB 서브넷에 `kubernetes.io/*` 태그 없음 | ✅ |
| ECR `scan_on_push = true` / `IMMUTABLE` | ✅ |
| S3 state — 암호화 + 버전관리 + 퍼블릭 차단 + `prevent_destroy` | ✅ |
| 비밀번호 BCrypt 해시만 저장 | ✅ 계약 (§6.8) |
| JWT HS256 + Secret 주입 | ✅ 계약 (§6.5) |
| 컨테이너 non-root | ✅ 계약 (§6.1) |

### 13.5 SG description 제약 — ASCII만

| 필드 | 한글 |
|---|---|
| `aws_security_group` 의 `description` / `ingress.description` / `egress.description` | ❌ **불가** |
| `tags` 값 | ✅ |
| ECR lifecycle policy `description` | ✅ |
| Terraform `variable` / `output` 의 `description` | ✅ (AWS에 전송되지 않음) |

```powershell
Select-String -Path ..\..\modules\*\*.tf -Pattern "description" | Select-String "[가-힣]"
```

---

## §14. 완료 기준(DoD) 체크리스트

### 14.1 인프라 리드
- [x] `backend-bootstrap` apply, 버킷명 반영
- [x] §8 선조치 완료
- [x] `terraform apply` 에러 0
- [x] `terraform output` 전 항목 공유
- [x] 팀원 전원 `kubectl get nodes` 성공
- [x] ACM 인증서 **Issued**
- [x] LB Controller Pod Running (차트 `3.5.0` 고정)
- [x] `app` 네임스페이스 생성
- [ ] `JWT_SIGNING_KEY` 발급 → BFF 담당 전달
- [ ] Cloudflare SSL/TLS = **Full (strict)**
- [ ] WAF / Rate Limit / Bot Fight 활성화
- [ ] `www` CNAME 등록 (🟠 주황)
- [ ] Tunnel 생성 + 토큰 BFF 담당 전달
- [ ] Access App 생성 + Policy Action = **Service Auth**
- [ ] **Protect with Access 활성화 + AUD 연결**
- [ ] Service Token 발급 + OKD팀 전달

### 14.2 EKS팀 공통
- [ ] `/healthz`, `/readyz` 200 (§6.1 의미대로)
- [ ] 이미지 git SHA 태그로 ECR 푸시 (amd64)
- [ ] 베이스 이미지 digest 핀
- [ ] 컨테이너 non-root 실행
- [ ] Deployment + Service 배포, Pod Running
- [ ] 하위 서비스 호출 성공
- [ ] 매니페스트 `k8s/` 커밋 (실제 Secret 미포함)
- [ ] URL 하드코딩 없음

### 14.3 EKS팀 담당별
- [ ] **WAS**: RDS 커넥션 로그 확인 / `sslMode=REQUIRED` 적용 / `JwtTokenProvider` 제거 완료 / X-Actor 2차 검증 동작
- [ ] **BFF**: Nimbus JWT 발급·검증 / 전달수단 바인딩 4케이스 / 외부 `X-Actor-*` 제거 / cloudflared Running + Tunnel **HEALTHY**
- [ ] **Web**: Ingress ADDRESS 표시 / Target Group **healthy** / `/api/bff/staff` 404

### 14.4 DB팀
- [ ] DDL / GRANT / SEED **git 커밋 완료**
- [ ] `commondb` 스키마 생성
- [ ] `app_was` 계정 + 최소 권한 + `REQUIRE SSL`
- [ ] WAS 담당에게 자격증명 전달
- [ ] 직원 seed (`must_change_password = 0`) 투입
- [ ] 예약 동시성 UNIQUE 제약 확인
- [ ] ✅ **v3.1** `04_icd_seed.sql` 투입 — `icd_code` **14,283** / `icd_code_synonym` **37,543**
- [ ] ✅ **v3.1** `chart.visit_no` UNIQUE / `prescription.chart_id` UNIQUE 확인
- [ ] ✅ **v3.1** `app_was` 가 `icd_code`·`icd_code_synonym` 에 **SELECT 권한만** 보유

### 14.5 전체 흐름 검증

**흐름1 (G2)**
- [ ] 브라우저 → `www` → patient-web 화면 표시
- [ ] `GET /auth/csrf` → `XSRF-TOKEN` 쿠키 수신
- [ ] 환자 회원가입 201
- [ ] 환자 로그인 → `PATIENT_TOKEN` 쿠키 설정
- [ ] 인증 후 환자 API 200
- [ ] 다른 환자 데이터 접근 시 404
- [ ] 5회 실패 시 **423**
- [ ] 로그아웃 시 쿠키 만료
- [ ] **외부 도메인에서 `/api/bff/staff/...` 호출 → 404**
- [ ] Cloudflare 대시보드에 트래픽 기록

**흐름2 (G3)**
- [ ] OKD Pod → **`200 application/json`** 수신
- [ ] 직원 로그인 → Bearer JWT (8시간)
- [ ] DOCTOR / NURSE / ADMIN_STAFF 권한 분리 동작
- [ ] Service Token 실패 시 **403**, 직원 JWT 실패 시 **401**, 역할 부족 시 **403**

**진료·처방 (G3 — ✅ v3.1)**
- [ ] `GET /staff/patients` → 당일 예약 목록 200
- [ ] `GET /staff/icd-codes?q=당뇨` → 50건 이하, 각 항목에 `code`·`name_kr`
- [ ] `GET /staff/icd-codes?q=E` (1자) → **400 `validation_error`**
- [ ] DOCTOR `POST /staff/charts` (처방 항목 1건 포함) → **201**
- [ ] 동일 `visit_no` 재요청 → **409 `duplicate_prescription`**
- [ ] NURSE `POST /staff/charts` → **403**
- [ ] 존재하지 않는 `icd_code` → **400 `validation_error`**
- [ ] `GET /staff/patients/{visit_no}/chart` → 차트 + 처방 + 항목 200
- [ ] 환자 로그인 → `GET /api/bff/patient/prescriptions` → **본인 처방만** 200
- [ ] 다른 환자의 `visit_no` 로 조회 → **404**
- [ ] `chart.icd_name_snapshot` 이 발급 시점 명칭으로 저장됨

**내부 통신**
- [ ] BFF가 외부 `X-Actor-*` 제거
- [ ] 검증한 JWT로 `X-Actor-*` 재생성
- [ ] WAS가 `X-Actor-Id`를 사용자 식별값으로 사용
- [ ] **`X-Trace-Id`가 BFF·WAS 로그에서 일치**

---

## §15. 트러블슈팅

### 15.1 최빈 사고 TOP 8

| 증상 | 원인 | 해결 |
|---|---|---|
| ACM 인증서 영구 **Pending Validation** | 검증 CNAME이 🟠 주황(프록시) | ⚪ 회색(DNS only)로 변경 |
| 브라우저 **무한 리다이렉트 루프** | Cloudflare SSL 모드 Flexible | **Full (strict)** |
| ALB Target Group **unhealthy** 영구 | `/healthz` 미구현 또는 경로 불일치 | 엔드포인트 구현 + annotation 경로 대조 |
| OKD에서 **HTML 로그인 페이지** 수신 | Access Policy Action이 `Allow` | **`Service Auth`** |
| 파드 `exec format error` | ARM 이미지 빌드 | `--platform linux/amd64` 재빌드 |
| **WAS 커넥션 100% 실패** | JDBC TLS 옵션 누락 | `sslMode=REQUIRED` (§13.2) |
| **환자 로그인은 되는데 API가 401** | 쿠키 `Path` 불일치 | `Path=/api/bff/patient` 확인 |
| **`/` 로만 라우팅되고 API가 Web으로 감** | Ingress에서 `/` 를 먼저 선언 | `/` 를 **마지막**으로 이동 (§6.9) |
| ✅ **ICD seed 적재 0건** | `완전코드구분='Y'` 로 필터 (**원본에 `Y`가 없다**) | `<> 'N'` 으로 교정 (§6.10) |
| ✅ **ICD seed `Duplicate entry` 실패** | 마스터 테이블에 37,543행 전량 INSERT | 마스터 14,283 / 동의어 37,543 분리 (§6.8) |
| ✅ **상병코드 한글이 `???`** | seed 파일 BOM 또는 `SET NAMES` 누락 | UTF-8 (BOM 없음) + `SET NAMES utf8mb4;` (§6.10) |
| ✅ **`/staff/icd-codes` 응답 수 초** | `name_kr` 인덱스 없음 → 37,543행 풀스캔 | §6.8 인덱스 3종 생성 후 `EXPLAIN` |
| ✅ **`SELECT command denied to user 'app_was'`** | 신규 테이블에 GRANT 누락 (§12.3 명시 부여 방식) | `02_grants.sql` 에 해당 테이블 추가 후 재실행 |
| ✅ **`app_was` 로 `Access denied` (비밀번호는 정확)** | `REQUIRE SSL` 계정에 비TLS 접속 | JDBC `sslMode=REQUIRED`. 로컬 compose 도 동일. `sslMode=DISABLED` 금지 |
| ✅ **`ERROR 1147 ... no such grant`** | DB 단위 GRANT 를 테이블 단위로 REVOKE 시도 | MySQL 미지원. 테이블 단위 명시 부여로 전환 (§12.3) |
| ✅ **`ERROR 1451` — ICD 재적재 실패** | `DELETE FROM icd_code` 를 차트 존재 상태에서 실행 | UPSERT 방식 사용 (§6.10). seed 재생성 |
| ✅ **적재는 됐는데 검색이 느림** | `ANALYZE TABLE` 누락 → 통계가 3행으로 인식 | `ANALYZE TABLE icd_code, icd_code_synonym;` |
| ✅ **`ConvertFrom-Json` 실패 (maxJsonLength)** | PowerShell 5.1 의 19MB JSON 파싱 한계 | `pwsh`(PS7)로 실행. 스크립트에 자동 폴백 내장 |
| ✅ **WAS 기동/테스트 실패 — `LenientObjectToEnumConverterFactory` `IllegalArgumentException`** | `application.yaml` 의 값이 enum 으로 변환 실패. **Jackson 3 에서 `WRITE_DATES_AS_TIMESTAMPS` 가 `SerializationFeature` → `DateTimeFeature` 로 이동** | `spring.jackson.serialization.write-dates-as-timestamps` **삭제**. Jackson 3 기본값이 이미 ISO-8601 이라 불필요 |
| ✅ **Gradle 테스트 로그 한글 깨짐** (`遺?몄뒪?몃옪`) | 데몬·테스트 JVM 의 `file.encoding` 이 CP949 | `gradle.properties` 에 `-Dfile.encoding=UTF-8`, `Test { defaultCharacterEncoding = "UTF-8" }`, PowerShell `[Console]::OutputEncoding = [Text.Encoding]::UTF8` |
| ✅ **테스트 실패했는데 원인 메시지가 안 보임** | Gradle 기본 출력은 예외 **클래스명만** 표시 | `testLogging { exceptionFormat = FULL; showCauses = true }` 또는 `build/reports/tests/test/index.html` 확인 |
| ✅ **WAS 기동 실패 — `Schema validation: wrong column type ... found [text], expecting [tinytext]`** | `@Lob` 만 붙이고 `length` 미지정. **MySQL 방언은 CLOB 의 실제 타입을 컬럼 길이로 고른다** (~255 tinytext / ~65535 text / ~16M mediumtext / 그 이상 longtext). 기본값 255 가 적용됨 | `@Column(length = 65535)` 로 DDL 의 `TEXT` 와 맞춘다. `ddl-auto: none` 은 우회일 뿐 |
| ✅ **`wrong column type ... found [tinyint unsigned], expecting [integer]`** | `TINYINT`/`SMALLINT` 컬럼을 `int`/`Integer` 로 매핑 | DDL 을 `INT` 로 통일 (§6.8). **Hibernate 는 첫 불일치에서 멈추므로 전 컬럼을 한 번에 점검할 것** |
| ✅ **`prepare.ps1` — `utf8NoBOM 을 유효한 열거자 이름과 일치시킬 수 없습니다`** | `-Encoding utf8NoBOM` 은 **PowerShell 7 전용**. 5.1 의 `-Encoding UTF8` 은 BOM 을 붙여 SQL 을 깨뜨린다 | `[System.IO.File]::WriteAllText(path, text, (New-Object System.Text.UTF8Encoding $false))` |
| ✅ **`.ps1` 실행 시 한글이 깨짐 (`寃쎈줈`)** | **PS 5.1 은 BOM 없는 `.ps1` 을 CP949 로 파싱한다.** `[Console]::OutputEncoding` 으로는 안 잡힌다 | `.ps1` 파일을 **UTF-8 BOM** 으로 저장 |
| ✅ **`.\gradlew` 인식 안 됨** | 새 머신에 래퍼 없음 | `gradle wrapper --gradle-version 9.5.1`. 이후 `gradle` 직접 호출 금지, **`.\gradlew` 만** 사용 |
| ✅ **예약 목록에는 뜨는데 예약하면 `400 invalid_date`** | 슬롯 조회가 날짜 범위(그날 00:00~)로만 잘라 **지나간 시각까지 반환**. 예약 검증은 현재 시각 기준 | 조회 시작점을 `max(그날 00:00, now)` 로. **조회 필터와 생성 검증의 판정 기준을 반드시 일치시킨다** |
| ✅ **필터가 만든 403 의 상태코드는 맞는데 본문이 빔** | 필터는 DispatcherServlet 밖이라 `getWriter()` 의 커밋 시점이 컨테이너에 좌우된다 | 바이트로 만들어 `setContentLength` → `getOutputStream()` → `flushBuffer()`. `reset()` 사용 시 `X-Trace-Id` 재설정 필수 |
| ✅ **검증 스크립트 전 항목이 `status=-1`** | `docker compose up -d` 는 컨테이너 **시작** 시점에 반환. Spring Boot 기동에 15초 더 필요 | `up -d --wait` 사용. **전 항목 동일 실패는 연결 문제의 신호다** — 항목별로 다르게 깨져야 애플리케이션 결함이다 |
| ✅ **`Could not find com.nimbusds:nimbus-jose-jwt:`** (버전이 빈 문자열) | **Spring Boot 4.1.0 BOM 은 nimbus-jose-jwt 를 관리하지 않는다.** Boot 3.x 는 관리했다. `spring-security-oauth2-jose` 미사용이라 전이 의존으로도 안 들어온다 | `build.gradle.kts` 에 버전 명시 (`10.9.1`). §5.3 버전 전량 핀 원칙 |
| ✅ **`class, interface, enum, or record expected`** + 뒤이어 `illegal character: '\u00a7'` 등 | **Javadoc 안의 `**/` 가 `*/` 로 해석되어 주석이 조기 종료.** 이후 한글 설명이 코드로 파싱된다. 콘솔의 깨진 한글은 CP949 표시 문제일 뿐 원인이 아니다 | 주석에서 `**/` 제거. **커밋 전 `grep -rn '\*\*/' --include='*.java'` 로 0건 확인** |
| ✅ **`cannot find symbol: AntPathRequestMatcher`** | **Spring Security 7 에서 `AntPathRequestMatcher` / `MvcRequestMatcher` 제거** (6.5 에서 deprecated). Boot 4.1 은 Security 7.1.0 을 끌어온다 | 문자열 오버로드(`ignoringRequestMatchers("/path/**")`) 또는 `PathPatternRequestMatcher.withDefaults().matcher(...)`. Security 7 DSL 은 URI 가 **절대경로**여야 한다 |
| ✅ **`No qualifying bean of type 'RestClient$Builder' available`** | **Spring Boot 4 는 자동 구성을 기능별 모듈로 분리했다.** `RestClient.Builder` 자동 구성이 `spring-boot-restclient` 로 이동했고 `starter-web` 은 이를 가져오지 않는다 (Boot 3 에서는 가져왔다) | `spring-boot-starter-restclient` 추가. **다른 기능도 동일한 함정이 있다** — Boot 3 예제를 그대로 옮기면 starter 누락으로 기동에서 터진다 |
| ✅ **BFF 경유 한글 검색만 0건** (WAS 직접은 정상) | **URI 이중 인코딩.** `UriUtils.encodeQueryParam` 으로 미리 인코딩한 문자열을 `RestClient.uri(String)` 에 넘기면 한 번 더 인코딩되어 `%` → `%25`. WAS 는 `%EB%8B%B9...` 리터럴로 검색한다 | 쿼리 값은 **URI 템플릿 변수**로 넘긴다: `get("/path?q={q}", actor, q)`. 문자열 연결 금지 |
| ✅ **환자 POST 가 두세 번째부터 403 forbidden** | CSRF 토큰을 최초 1회만 읽어 캐시. 토큰이 갱신되면 이후 요청이 전부 거부된다. 인가 문제로 오진하기 쉽다 (CSRF 실패도 `AccessDeniedHandler` 를 탄다) | 브라우저와 동일하게 **매 요청 직전 쿠키를 다시 읽는다** |
| ✅ **`PATIENT_TOKEN` / `XSRF-TOKEN` 쿠키를 못 읽음** | 쿠키가 `Path=/api/bff/patient` 인데 루트 URI 로 조회. `CookieContainer.GetCookies(루트)` 는 경로 제한 쿠키를 반환하지 않는다 | 조회 URI 에 경로 포함. **쿠키 Path 축소는 계약대로다 — 조회 쪽이 틀린 것** |
| ✅ **상위 서비스 401 만 본문이 빈다** (`Content-Length: 0`). 409·400 은 정상 | **`SimpleClientHttpRequestFactory`(HttpURLConnection) 가 401 을 인증 협상으로 보고 에러 스트림을 소비한다.** 401 만 선택적으로 깨지므로 원인 추적이 매우 어렵다 | `JdkClientHttpRequestFactory`(JDK HttpClient) 로 교체. connect timeout 은 `HttpClient.Builder`, read timeout 은 팩토리에 설정 |
| ✅ **Security 계층 오류 응답에 `X-Trace-Id` 헤더가 없고 `trace_id: null`** | 필터·핸들러에서 `HttpServletResponse.reset()` 호출. **reset() 은 이미 설정된 모든 헤더를 지운다** — `TraceIdFilter` 의 헤더와 Security 가 큐에 넣은 `Set-Cookie` 가 함께 사라진다 | `reset()` 을 쓰지 않는다. 상태·본문만 덮어쓴다. `trace_id` 는 **MDC → 응답 헤더 → 신규 생성** 3단으로 확보해 null 을 내보내지 않는다 |
| ✅ **로그인 5회 실패 잠금이 작동하지 않음** | **인증 실패는 예외로 응답하고, 예외는 트랜잭션을 롤백한다.** 같은 트랜잭션에서 실패 카운터를 올리면 증가분이 함께 사라진다. 응답은 정상이라 어떤 시나리오도 잡지 못한다 | 카운터 증가를 **`@Transactional(propagation = REQUIRES_NEW)`** 별도 빈으로 분리. **자기호출은 프록시를 타지 않으므로 반드시 다른 빈이어야 한다.** 5회 실패 → 423 시나리오를 검증에 추가 |
| ✅ **파드 기동 직후 첫 요청만 `503 upstream_unavailable`** | WAS 콜드스타트(Hibernate SQL 생성 + BCrypt + MVC 초기화)가 BFF read timeout 5초를 초과. 실측 `ResourceAccessException` | 타임아웃 계약은 유지한다. **WAS 파드에 `startupProbe`** 를 건다. 검증 스크립트는 워밍업 요청을 먼저 보낸다 |
| ✅ **`NativeCommandError` 로 스크립트가 즉시 중단** (실패가 아닌데도) | **`$ErrorActionPreference='Stop'` 에서는 네이티브 명령이 stderr 에 한 줄만 써도 종료 오류로 승격된다.** `aws ecr describe-images` 의 "이미지 없음"은 정상 경로인데 stderr 로 나온다 | `aws`/`docker`/`kubectl` 을 쓰는 스크립트는 `'Continue'` 로 두고 판정을 **전부 `$LASTEXITCODE`** 로 명시한다 |
| ✅ **롤아웃이 `0 out of N new replicas` 에서 멈추고 파드가 0개** | **ResourceQuota 의 `limits.cpu` 소진.** 파드가 아예 생성되지 않아 `describe pod`·`describe rs` 가 전부 비어 있다. 증상만 보면 원인이 안 보인다 | `kubectl -n app describe resourcequota` 로 `Used/Hard` 확인. **개별 파드 limits × 파드 수 ≤ quota** 를 항상 함께 계산한다 |
| ✅ **`Apply failed with N conflicts: kubectl-client-side-apply`** | 과거 `kubectl apply -f`(client-side)로 만든 리소스의 필드 소유권이 남아 server-side apply 가 거부 | `--force-conflicts` 로 소유권 인수. 삭제가 아니라 이전이다 |
| ✅ **`Set-Content -Encoding UTF8` 이 파일을 손상** | PS 5.1 은 **BOM 을 붙이고** 원본을 CP949 로 읽는다. YAML 의 BOM 은 첫 키를, Dockerfile 의 BOM 은 `FROM` 을 깨뜨린다 | `[System.IO.File]::WriteAllText(절대경로, text, (New-Object System.Text.UTF8Encoding $false))`. **.NET 은 PowerShell 의 현재 위치를 모른다 — 반드시 `Resolve-Path`** |
| ✅ **브라우저에서만 모든 POST 가 403.** 검증 스크립트는 통과 | **CSRF 쿠키의 `Path` 를 `/api/bff/patient` 로 축소했다.** `document.cookie` 는 **현재 문서 경로**에 해당하는 쿠키만 반환하는데 화면은 `/` 에서 열린다. JS 가 토큰을 영원히 못 읽는다. PowerShell `CookieContainer` 는 경로를 지정해 조회하므로 이 결함을 놓친다 | **`XSRF-TOKEN` 의 Path 는 `/`.** JS 가 읽어야 하는 쿠키이기 때문이다. Path 축소는 `PATIENT_TOKEN`(HttpOnly) 에만 적용한다. 검증에 **루트 경로 조회** 시나리오를 추가한다 |
| ✅ **응답 본문의 한글이 `êµ¬ì¤í¼í` 로 읽힘** | nginx 가 `Content-Type` 에 charset 을 붙이지 않아 클라이언트가 임의 해석 (PS 5.1 은 Latin-1). 브라우저는 `<meta charset>` 을 읽기 전에 헤더를 먼저 본다 | nginx 에 `charset utf-8; charset_types ...`. 검증은 **ASCII 마커로 판정**하고 인코딩은 헤더로 따로 확인 |
| ✅ **G3 검증: `Service Token 없이 접근 차단` `status=403` 인데 FAIL** | **Cloudflare Access 의 차단 응답 자체가 `text/html` 이다** (자체 오류 페이지). 검증 스크립트가 이를 "Policy 가 Allow" 신호와 같은 것으로 오판했다 — `Content-Type` 으로 판정한 것이 잘못. 정확히 계약대로 동작 중이었다 | 판정은 **상태코드만** 본다. `302`/`200`(로그인 폼) 은 별도 항목으로 분리해 Allow 오설정을 잡는다 |

### 15.2 진단 명령

```bash
kubectl get nodes -o wide
kubectl -n app describe pod <파드명>            # ImagePull/CrashLoop 원인
kubectl -n app logs <파드명> --previous         # 재시작 직전 로그
kubectl -n app get endpoints                    # 비어 있으면 셀렉터 라벨 불일치
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

**흐름1 경로 검증 (외부에서)**

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://www.kuspitalsoldeskproject.org/
curl -s -o /dev/null -w "%{http_code}\n" https://www.kuspitalsoldeskproject.org/api/bff/patient/auth/csrf
curl -s -o /dev/null -w "%{http_code}\n" https://www.kuspitalsoldeskproject.org/api/bff/staff/auth/login   # 404 여야 정상
```

### 15.3 증상별 원인 매핑

| 증상 | 확인 순서 |
|---|---|
| `ImagePullBackOff` | ① 태그 오타 ② ECR 리포지토리 존재 ③ 노드 IAM ECR 권한 |
| `CrashLoopBackOff` | ① `logs --previous` ② 아키텍처 불일치 ③ 필수 환경변수 누락 |
| `endpoints` 비어 있음 | Service `selector` ↔ Pod `labels` 불일치 |
| 서비스 간 호출 timeout | ① 대상 Pod Running ② Service 포트 ③ DNS 이름 오타 |
| RDS 접속 timeout | ① 파드가 `app` 네임스페이스인지 ② RDS SG ③ 엔드포인트 오타 |
| RDS 접속 즉시 거부 | TLS 옵션 누락 (§13.2) |
| BFF 401 반복 | 전달수단 ↔ actor_type 불일치 (§6.5) |
| BFF 503 `upstream_unavailable` | WAS Pod 상태 / `was-svc` endpoints |
| `terraform init` 실패 | `backend.tf` ↔ 부트스트랩 버킷명 불일치 |

---

## §16. 금지 사항

| # | 금지 행위 | 이유 |
|---|---|---|
| 1 | 인프라 리드 외 인원의 `terraform apply` | 단일 state 손상 |
| 2 | `backend-bootstrap` 재실행 | `prevent_destroy` 충돌 |
| 3 | `*.tfstate`, `*.tfvars`, 실제 Secret 커밋 | 자격증명 유출 |
| 4 | 이미지 `:latest` 태그 (**cloudflared 포함**) | `IMMUTABLE` 위반, 롤백 추적 불가 |
| 5 | RDS SG에 개인 IP 임시 허용 | 격리 설계 무력화 |
| 6 | DB 서브넷에 `kubernetes.io/*` 태그 | LBC가 DB 계층에 ENI 배치 |
| 7 | `admin` 계정을 앱에 직접 사용 | 최소 권한 위반 |
| 8 | 서비스 URL 코드 하드코딩 | 네임스페이스 변경 시 전면 재빌드 |
| 9 | 뼈대 완성 전 기능 추가 | 통합 지점 불안정화 |
| 10 | Cloudflare 설정을 Terraform으로 이관 | §0.4-2 위반 |
| 11 | **ALB Ingress에 `/api/bff/staff` 규칙 추가** | 직원 API 외부 노출 |
| 12 | **WAS에서 JWT 발급** | §6.5 책임 분리 위반 |
| 13 | **BFF에서 DB 직접 접근 / 비밀번호 해싱** | 동일 |
| 14 | **인증 POST 자동 Retry** | 중복 가입, 잠금 조기 발동 |
| 15 | **`roles` 배열 사용** | `role` 단수 문자열로 확정 |
| 16 | **비밀번호·토큰 로그 출력 / 인증 API body 전체 로깅** | 자격증명 유출 |
| 17 | **`kubectl delete -f k8s/`** | Namespace 포함 시 하위 전체 캐스케이드 삭제 |
| 18 | **`staff-api` DNS 레코드 수동 생성** | Tunnel 자동 생성분과 충돌 |
| 19 | ✅ **v3.1 — WAS 런타임에서 외부 공공데이터 API 직접 호출** | §7.11 단일 NAT SPOF 확대 |
| 20 | ✅ **v3.1 — 처방 발급용 신규 API 경로 추가** | §7.12 검증 범위 재확대 |
| 21 | ✅ **v3.1 — `chart.icd_name_snapshot` 을 마스터 갱신에 맞춰 소급 수정** | 의료 기록 무결성 위반 |

---

## §17. 백로그

**뼈대(G3) 완성 전에는 착수하지 않는다.**

### 17.1 확정 완료 (재논의 금지)

§21 확정 결정 로그 참조.

### 17.2 운영 전환 시 필수 변경

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

### 17.3 기능 백로그

- Cognito / Refresh Token / MFA / JWT 키 회전 / 강제 폐기 목록
- 직원 최초 비밀번호 강제 변경, 관리자 수동 잠금 해제
- 다중 역할(`roles` 배열), `RECEPTION` / `BILLING` 역할
- **NetworkPolicy** — cloudflared→BFF, BFF→WAS, WAS→RDS만 허용
  > L3/L4 통제다. `/api` 경로 같은 L7 통제를 대신하지 않는다. 경로 통제는 ALB Ingress · Cloudflare Access · BFF Security가 담당한다.
- mTLS / Service Mesh
- CI/CD (GitHub Actions → ECR → EKS)
- HPA / Karpenter
- 관측성: Container Insights, Prometheus + Grafana, OpenTelemetry
- RDS CMK
- VPC Endpoint (ECR, S3, Secrets Manager) — NAT 비용 절감
- 환경 분리 (`envs/stg`, `envs/prd`) 및 state 분리
- apex 도메인(`kuspitalsoldeskproject.org`) 처리

**✅ v3.1 추가**

- **ICD 마스터 자동 동기화** — 공공데이터포털 API를 호출하는 일회성 `Job` 또는 `CronJob`. WAS와 분리 필수(§7.11). 서비스키는 Secrets Manager 경유
- **의약품 표준코드 연동** — 현재 `prescription_item.drug_name` 은 자유 텍스트. 의약품안전나라 코드 마스터 도입 시 FK로 승격
- **처방 수정·취소 API** — `PATCH` / `DELETE /api/bff/staff/charts/{id}` (§7.12 대가)
- **부상병(부상병코드) 다중 등록** — 현재 차트당 상병코드 1개
- **처방전 PDF 발급 / 전자서명**
- **ICD 검색 성능** — 37,543행 `LIKE '%키워드%'` 는 인덱스를 타지 않는다. 부분일치 요구가 커지면 **FULLTEXT 인덱스 + ngram 파서** 로 전환

**✅ v3.2 추가 (P2 이관)**

- **`SameSite=Lax` 실동작 검증** — 외부 링크 진입 흐름. 스크립트로는 판정 불가, 브라우저 수동 확인
- **`UserDetailsServiceAutoConfiguration` 명시적 비활성화** — 현재 무해하나 자동 구성이 인증 경로에 개입할 여지를 남긴다
- **검증 스크립트 표시 폭 패딩** — 한글은 폭이 2다. `"{0,-48}"` 은 문자 수로 세어 정렬이 깨지고 로그 오독 위험이 있다
- **RDS 검증 데이터 정리** — `verify-*` 실행마다 환자·예약·차트가 쌓인다. 시연 데이터와 분리할지 판단
- **WAS/BFF startupProbe 튜닝** — 현재 150초. 실측 기동은 12~15초다
- **`patient-web` 화면 확장** — 현재 최소 구현. 예약 취소·진료 기록 조회 미구현

---

## §18. 온프레미스(OKD)팀 가이드

> OKD팀은 **AWS 계정도, AWS 자격증명도, VPN도 전혀 필요 없다.**

### 18.1 역할 정의

| 구분 | 내용 |
|---|---|
| ✅ 담당 | OKD Web Pod가 Cloudflare Access 엔드포인트를 **서버사이드에서 HTTPS 호출** |
| ✅ 담당 | Service Token·직원 JWT를 **서버사이드에 보관** |
| ❌ 비담당 | cloudflared 배포 (EKS BFF 담당) |
| ❌ 비담당 | Tunnel 생성, Access App/Policy 구성 (인프라 리드) |
| ❌ 불필요 | VPN, IPsec, Direct Connect, 인바운드 방화벽 오픈 |

### 18.2 아키텍처상 위치

```
[사내망 OKD]                       [Cloudflare 엣지]           [AWS EKS]
Web Pod ──HTTPS 443──→ Access(Service Token 검증) → Tunnel ──→ cloudflared ──→ bff-svc
        (아웃바운드)                                         (아웃바운드로 사전 연결)
```

**양쪽 모두 아웃바운드 연결만** 한다. 엣지에서 두 연결이 만난다. 사내망에 인바운드 포트를 열 필요가 없다 — 이 아키텍처를 선택한 이유다.

### 18.3 사전 확인 (P0 — 지금 바로)

| # | 확인 항목 | 실패 시 |
|---|---|---|
| 1 | OKD 워커에서 **아웃바운드 443** 허용 | 연결 불가 |
| 2 | 사내 DNS가 공인 도메인 해석 | 호스트명 조회 실패 |
| 3 | 사내 Forward Proxy 존재 여부 | 프록시 환경변수 필요 |
| 4 | 프록시의 **TLS MITM 검사** 여부 | 사내 CA 주입 필요 |
| 5 | Pod 아웃바운드 Egress Policy 제한 | 예외 규칙 추가 |

```bash
curl -sv https://www.cloudflare.com --max-time 10
nslookup staff-api.kuspitalsoldeskproject.org
env | grep -i proxy
```

> ⚠️ 방화벽 정책 변경은 사내 승인에 며칠이 걸린다. **가장 먼저 착수한다.**

### 18.4 인프라 리드에게 수령할 항목

| 항목 | 형태 |
|---|---|
| 내부 도메인 | `https://staff-api.kuspitalsoldeskproject.org` |
| Service Token **Client ID** | `xxxxx.access` |
| Service Token **Client Secret** | 긴 문자열 |

> 🔒 Secret은 **1회만 표시**된다. 분실 시 재발급.

### 18.5 호출 방식 — 2계층 인증

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

### 18.6 OKD 리소스 구성

```bash
oc create secret generic cf-access-token \
  --from-literal=CF_ACCESS_CLIENT_ID='<CLIENT_ID>' \
  --from-literal=CF_ACCESS_CLIENT_SECRET='<CLIENT_SECRET>' \
  -n <내부-네임스페이스>
```

```yaml
spec:
  template:
    spec:
      containers:
        - name: internal-web
          env:
            - name: BFF_BASE_URL
              value: "https://staff-api.kuspitalsoldeskproject.org"
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
| 11 | 표준 enum(`BOOKED` 등) → **직원 화면 한글 라벨 변환은 OKD Web이 수행** | §6.8 |

### 18.8 🚨 최빈 실패 — HTML 응답 수신

| 원인 | 확인 | 조치 주체 |
|---|---|---|
| Access Policy Action이 `Allow` | 대시보드 | **인프라 리드** |
| Protect with Access 미활성 / AUD 불일치 | 대시보드 | **인프라 리드** |
| 헤더 이름 오타 | `curl -v` | OKD팀 |
| Client Secret에 개행·공백 혼입 | Secret 재생성 | OKD팀 |

```bash
curl -s -o /dev/null -w "%{http_code} %{content_type}\n" \
  https://staff-api.kuspitalsoldeskproject.org/api/bff/staff/patients \
  -H "CF-Access-Client-Id: <ID>" -H "CF-Access-Client-Secret: <SECRET>"
```

- `200 application/json` 또는 `401 application/json` → **Access 통과 (정상)**
- `302` 또는 `200 text/html` → 위 표대로 추적

> 📌 **401 JSON은 좋은 신호다.** Access를 통과해 BFF까지 도달했다는 뜻이다(JWT가 아직 없을 뿐).

### 18.9 사내 프록시 / TLS 검사 대응

```yaml
env:
  - name: HTTPS_PROXY
    value: "http://proxy.internal:3128"
  - name: NO_PROXY
    value: "localhost,127.0.0.1,.svc,.cluster.local"
```

프록시가 TLS MITM 검사를 하면 **사내 CA를 ConfigMap으로 마운트**하고 언어별 신뢰 저장소에 등록한다. 미조치 시 `certificate verify failed`로 전부 실패한다.

### 18.10 OKD팀 DoD

- [ ] 아웃바운드 443 허용 확인
- [ ] 공인 도메인 DNS 해석 확인
- [ ] 프록시 / TLS 검사 대응 완료
- [ ] Service Token을 OpenShift Secret으로 생성 (이미지 하드코딩 없음)
- [ ] Web Pod → **`200 application/json`** 수신
- [ ] 직원 로그인 → Bearer JWT 획득 → 업무 API 성공
- [ ] 역할별 화면 분기 동작
- [ ] 타임아웃 / 재시도 정책 적용 (인증 POST 제외)
- [ ] 토큰이 로그·브라우저에 남지 않음 확인

### 18.11 인터페이스 — ✅ 확정 (v3.0)

> **경로 분리로 확정되었다.** v2.1의 "공통 API 공유 권장"은 폐기한다.
> OKD Web은 `/api/bff/staff/**` 만 호출한다. `/api/bff/patient/**` 호출 금지.
> API 스펙은 §6.6 계약이 전부다. 별도 합의 절차 없음.

---

## §19. P0 기록 및 교훈

> 기준일 2026-08-08 / 상태 **완료**

### 19.1 확정된 값

| 항목 | 값 |
|---|---|
| AWS 계정 | `597106152264` |
| 리전 | `ap-northeast-2` |
| S3 state 버킷 | `hybrid-toy-tfstate-kuspital` |
| Kubernetes | `1.35` |
| 외부 도메인 (흐름1) | `www.kuspitalsoldeskproject.org` |
| 내부 도메인 (흐름2) | `staff-api.kuspitalsoldeskproject.org` |
| ECR 태그 정책 | `IMMUTABLE` |
| RDS 마스터 비밀번호 | Secrets Manager 자동 관리 |
| RDS TLS | `require_secure_transport` |
| apply 주체 | `user/team03` |

해석된 버전: `aws 6.58.0` · `eks 21.24.2` · `vpc 5.21.0` · `iam 5.60.0` · `kms 4.0.0`

### 19.2 IAM 권한 현황

| User | `eks:DescribeCluster` (인라인) | `AmazonEC2ContainerRegistryPowerUser` | Secrets Manager |
|---|---|---|---|
| kusweb | ✅ | ✅ | — |
| kusbff | ✅ | ✅ | — |
| kuswas | ✅ | ✅ | — |
| kusdb | ✅ | — | ✅ (인라인) |

> `eks:DescribeCluster`만 부여하는 AWS 관리형 정책은 없다 — 인라인으로 작성한다.
> 인라인 정책은 `list-attached-user-policies`에 **나오지 않는다.** `list-user-policies`로 확인한다.

### 19.3 apply 재진입 전 수정한 코드 결함 4건

| # | 결함 | 위치 | 영향 |
|---|---|---|---|
| 1 | EKS 애드온 `before_compute` 미지정 | `modules/eks/main.tf` | 🔴 **apply 실패** |
| 2 | DB 서브넷 전용 RT 미생성 | `modules/network/main.tf` | 🟠 격리 설계 무효 |
| 3 | `developer_iam_arns` 키 역전 (web↔bff) | `envs/dev/main.tf` | 🟡 권한 축소 시 발현 |
| 4 | `alb_domain_name` 마크다운 문법 혼입 | `terraform.tfvars` | 🟠 ACM 발급 실패 |

**① 애드온 설치 순서 — apply 실패의 직접 원인**

`terraform-aws-modules/eks` v20+ 는 `bootstrap_self_managed_addons` 기본값이 `false`다. **클러스터가 CNI 없이 생성**된다.

```
클러스터 → 노드그룹 → 노드 부팅 → CNI 부재 → 파드 IP 할당 불가
→ 노드 영구 NotReady → 33분 타임아웃 → NodeCreationFailure
```

```hcl
addons = {
  coredns    = {}
  kube-proxy = {}
  vpc-cni                = { before_compute = true }   # 필수
  eks-pod-identity-agent = { before_compute = true }   # 필수
}
```

> 📌 **노드 부팅 시점에 필요한 애드온은 전부 `before_compute = true`.**

**② DB 서브넷이 NAT 경로를 공유하고 있었음**

```hcl
create_database_subnet_route_table = true    # 격리 성립
create_database_subnet_group       = false   # §7.3 중복 방지
```

> ⚠️ **두 인자는 역할이 다르다.**

### 19.4 apply 전 코드 점검 명령 (`envs/dev` 기준)

```powershell
Get-ChildItem ..\..\modules -Recurse -Filter "*.tf" | Select-String "before_compute"
Select-String -Path ..\..\modules\network\main.tf -Pattern "create_database_subnet_route_table"
Get-ChildItem ..\..\modules -Recurse -Filter "*.tf" | Select-String "manage_master_user_password|^\s*password\s*="
Select-String -Path .\main.tf -Pattern "kusweb|kusbff|kuswas|kusdb"
Select-String -Path ..\..\modules\*\*.tf -Pattern "description" | Select-String "[가-힣]"
```

**plan.txt 필수 대조**

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

> 🚨 **plan 파일을 거치지 않은 apply는 위 4건을 전부 통과시킨다.**

### 19.5 P0 교훈

| 함정 | 증상 | 대응 |
|---|---|---|
| 안내문의 `# ~에 추가`를 새 블록으로 복사 | `Duplicate resource` | "추가"는 **기존 블록 안에 한 줄** |
| 모듈 입력 인자를 블록 밖에 작성 | `argument ... is not expected here` | `fmt` 후 들여쓰기 확인 |
| 호출부만 쓰고 변수 선언 누락 | 동일 에러 | 모듈 인자는 **호출부 + 선언부** 양쪽 |
| 리포 루트에서 `validate` | `Success!` — 검증 대상 0개 | `envs/dev`와 `backend-bootstrap`에서 각각. 재귀는 `fmt -recursive`뿐 |
| 버킷 생성 전 `validate` | backend 초기화 실패 | `terraform init -backend=false` (버킷 생성 후에는 **금지**) |
| PC 이동 후 `validate` | `Module not installed` | `.terraform/`은 로컬 캐시 — `init` 재실행 |
| upstream 모듈 deprecated 경고 | `name is deprecated...` | **조치 불필요.** `.terraform/` 하위면 우리 코드 아님 |
| 모듈 output 미노출 | `helm install`에서 값 없음 | apply **전에** output 목록 ↔ G1 공유 항목 대조 |
| 모듈 기본값을 의도와 같다고 가정 | CNI 미설치 | 기본값은 **반드시 문서 확인** |
| 문서상 설계가 코드에 미반영 | "완전 격리"인데 NAT 공유 | 설계 문장마다 **대응 인자를 코드에서 확인** |
| 렌더링된 값을 복사 | 도메인에 `[...](...)` 혼입 | **raw 복사 + 명령으로 검증** |
| `validate` 통과를 정상으로 오인 | 문법만 검증 | plan 육안 검토가 유일한 방어선 |
| §5 버전 표를 그대로 신뢰 | 1.33 표준 지원 종료 → 6배 요금 | 버전 표는 유통기한이 있다 |

---

## §20. P1 실행 기록 및 교훈

> 기준일 2026-08-10 / 상태 **🚩 G1 통과, P2 진입**

### 20.1 생성된 리소스 — G1 공유 항목

```
EKS 클러스터명     : hybrid-toy-eks
kubeconfig         : aws eks update-kubeconfig --region ap-northeast-2 --name hybrid-toy-eks
클러스터 엔드포인트 : https://73DC9589D0580B53CFB4FDB4C59B297A.gr7.ap-northeast-2.eks.amazonaws.com
네임스페이스        : app

ECR
  patient-web : 597106152264.dkr.ecr.ap-northeast-2.amazonaws.com/hybrid-toy/patient-web
  bff         : 597106152264.dkr.ecr.ap-northeast-2.amazonaws.com/hybrid-toy/bff
  was         : 597106152264.dkr.ecr.ap-northeast-2.amazonaws.com/hybrid-toy/was

RDS 엔드포인트     : hybrid-toy-rds.cfmws2co6i6j.ap-northeast-2.rds.amazonaws.com : 3306
RDS 마스터 시크릿   : arn:aws:secretsmanager:ap-northeast-2:597106152264:secret:rds!db-83b090eb-78f5-4c86-8c9d-5f242c6b4cc9-vPq6SX
ACM 인증서         : arn:aws:acm:ap-northeast-2:597106152264:certificate/6eecdf13-ea45-4847-964b-ae9642308f87
LBC IRSA 역할      : arn:aws:iam::597106152264:role/hybrid-toy-eks-lbc-irsa
```

| 리소스 | ID |
|---|---|
| VPC | `vpc-0eaa396d5e9eae015` |
| Public Subnet | `subnet-0f55d9efac8f2b6b0`, `subnet-01ab1a42f616a2733` |
| Private Subnet | `subnet-03e4de8d6064f96a1`, `subnet-008571088a2c53a6f` |
| Database Subnet | `subnet-056a7517df20bb615`, `subnet-030857d1a7b2d75c9` |
| Database RT | `rtb-086678314e73d8b93` |
| NAT Gateway | `nat-07f604e7d0bbba903` |

### 20.2 생성 소요 시간

| 리소스 | 소요 |
|---|---|
| ECR ×3 + lifecycle ×3 | 1초 |
| VPC / 서브넷 / RT / IGW | 1~2초 |
| NAT Gateway | 1분 44초 |
| KMS Key | 21초 |
| EKS 클러스터 | 7분 43초 |
| 애드온 `before_compute` | 44초 |
| **노드그룹** | **1분 48초** |
| coredns / kube-proxy | 15초 / 25초 |
| RDS 인스턴스 | 6분 20초 |

> **노드그룹 1분 48초** — §19.3-① 수정의 실물 검증. 이전 apply는 CNI 부재로 33분 대기 후 실패했다.

### 20.3 LB Controller 설치 — 확정 절차

멀티라인 붙여넣기로 ARN이 절단되는 사고가 발생했다. **식별자는 사람 손을 거치지 않는다: `output -raw` → 변수 → 1줄 명령.**

```powershell
helm repo add eks https://aws.github.io/eks-charts
helm repo update

$lbcRoleArn = terraform output -raw lbc_irsa_role_arn
$vpcId      = aws eks describe-cluster --name hybrid-toy-eks --region ap-northeast-2 --query "cluster.resourcesVpcConfig.vpcId" --output text
$annotation = "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$lbcRoleArn"

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --version 3.5.0 --set clusterName=hybrid-toy-eks --set region=ap-northeast-2 --set vpcId=$vpcId --set serviceAccount.create=true --set serviceAccount.name=aws-load-balancer-controller --set-string $annotation
```

**검증 — 3단계 전부**

```powershell
helm get values aws-load-balancer-controller -n kube-system     # ① vpcId / region / role-arn 승계
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller   # ② Running, RESTARTS 0
kubectl get ingressclass                                        # ③ alb / ingress.k8s.aws/alb
```

> 📌 `region` / `vpcId`를 **명시 주입**한다. 런타임 자동탐색은 IMDS `hop_limit=1`과 충돌해 CrashLoop을 일으킨다. hop limit 상향은 파드가 노드 IAM을 탈취할 경로를 여는 방향이라 채택하지 않았다.
> 📌 로그가 `Attempting to acquire leader lease...`에서 멈춘 것처럼 보이는 건 **정상**이다. standby도 webhook을 서빙하므로 Readiness를 통과한다.
> 📌 **`1/1 Running`은 leader lease 획득까지만 증명한다.** AWS API 호출 성공은 첫 Ingress 생성 때 드러난다.

### 20.4 파라미터 그룹 상시 drift — v3.0에서 해소

AWS가 `ON`을 `1`로 정규화하여 매 plan마다 diff가 재출현했다. 기능 영향은 없으나 **무해한 diff가 상시로 뜨면 진짜 diff를 놓친다.** §13.2대로 `value = "1"`로 확정했다.

### 20.5 서브넷 태그 실물 대조

| 서브넷 | Tier | `role/elb` | `role/internal-elb` |
|---|---|---|---|
| `subnet-0f55d9efac8f2b6b0` | Public | `1` | — |
| `subnet-01ab1a42f616a2733` | Public | `1` | — |
| `subnet-03e4de8d6064f96a1` | Private | — | `1` |
| `subnet-008571088a2c53a6f` | Private | — | `1` |
| `subnet-056a7517df20bb615` | **Database** | **없음** | **없음** |
| `subnet-030857d1a7b2d75c9` | **Database** | **없음** | **없음** |

> 격리 설계가 **라우트 테이블과 태그 양쪽에서** 성립한다. Public 2개가 서로 다른 AZ이므로 `internet-facing` ALB 배치 요건(최소 2 AZ)도 충족.

### 20.6 `app` 네임스페이스 소유권 이관

| 시점 | 주체 | 조치 |
|---|---|---|
| G1 | 인프라 리드 | `kubectl create namespace app` (언블로킹용 예외) |
| P2 초반 | EKS팀 | `k8s/namespace.yaml` 커밋 → `kubectl apply --server-side -f` |
| 이후 | EKS팀 | 이 파일이 유일한 정의 |

> `create`로 만든 리소스는 `last-applied-configuration`이 없어 첫 `apply` 시 경고가 뜬다. `--server-side`를 쓰면 흡수된다.

### 20.7 팀원 온보딩 안내문

```
1. winget install -e --id Amazon.AWSCLI
   winget install -e --id Kubernetes.kubectl
   → 설치 후 PowerShell 새 창을 열 것
2. aws configure          (AccessKey / SecretKey / ap-northeast-2 / json)
3. aws sts get-caller-identity                                            ← 본인 계정명 확인
4. aws eks update-kubeconfig --region ap-northeast-2 --name hybrid-toy-eks
5. kubectl get nodes                                                      ← Ready 2개

※ 4번을 건너뛰면 localhost:8080 오류. 클러스터 장애 아님.
※ 명령을 여러 줄로 나누지 말 것.
```

### 20.8 P1 교훈

| 함정 | 증상 | 대응 |
|---|---|---|
| SG description에 한글 | apply 중단 | SG description은 **ASCII만** (§13.5) |
| AWS 측 값 정규화 | `ON` → `1` 상시 drift | AWS 반환값에 맞춘다 |
| PowerShell `-target` 파싱 | `Prefix "module." must be followed by...` | `"-target=module.ecr"` 인용 |
| `kubectl` 미설치 | `update-kubeconfig`는 성공 | 별개 도구다 |
| kubeconfig 미등록 | `localhost:8080` 폴백 | 클러스터 장애 아님. **PC를 옮기면 매번 필요** |
| state 비었는데 AWS 미확인 | orphan 과금 + `AlreadyExists` | `state list` **와** AWS 실물 양쪽 확인 |
| **멀티라인 백틱 붙여넣기** | ARN 절단 → `arn:aws:ia` | `output -raw` → 변수 → 1줄. ARN은 `--set-string` |
| **Helm `deployed` = 정상 오인** | annotation 값은 검증되지 않는다 | 설치 직후 **명령으로 대조** |
| **컨트롤러 런타임 자동탐색** | IMDS hop limit 충돌 → CrashLoop | **명시 주입**이 항상 낫다 |
| **Helm 차트 버전 부동** | 재설치 시 다른 버전 유입 | `--version` 고정 |
| **정책 "생성"과 "연결" 혼동** | 정책은 있는데 권한 미적용 | 최종 검증은 **실제 API 호출** |
| 마크다운 문법 혼입 (2회차) | ARN·도메인 오염 | 교훈이 실행에 반영되지 않았다. **프로세스로 강제** |
| **작업 디렉터리 다중화** | `tfvars` 사본마다 내용 상이 | 정본 1개만 남긴다 (`F:\myterraform`) |
| **`$env:AWS_PROFILE`은 세션 스코프** | 창 닫으면 소실 | apply 직전 `sts get-caller-identity` |

> **가장 비쌌던 교훈:** 값이 아니라 **입력 경로**가 문제였다. `alb_domain_name` 오염과 LBC ARN 절단은 원인이 같다 — 렌더링된 텍스트를 콘솔에 붙여넣었다.

---

## §21. 확정 결정 로그

> **이 표의 항목은 재논의하지 않는다.** 변경하려면 이 문서를 먼저 고치고 PR을 올린다.

| # | 항목 | 확정 | 근거 | 확정일 |
|---|---|---|---|---|
| 1 | RDS TLS 강제 | 적용 (`require_secure_transport`) | §13.2 | 2026-08-07 |
| 2 | RDS 마스터 비밀번호 | Secrets Manager | §13.3 | 2026-08-07 |
| 3 | RDS CMK | 미적용 (백로그) | 오버스펙 | 2026-08-07 |
| 4 | ECR 태그 정책 | `IMMUTABLE` | §8.3 | 2026-08-07 |
| 5 | 내부 도메인 | `staff-api.kuspitalsoldeskproject.org` | — | 2026-08-08 |
| 6 | Kubernetes | `1.35` | 표준 지원 구간 | 2026-08-08 |
| 7 | LBC Chart | `3.5.0` 고정 | §20.3 | 2026-08-10 |
| 8 | **파라미터 값 표기** | `require_secure_transport = "1"` | drift 제거 | **2026-08-10** |
| 9 | **Ingress 경로** | 2-path, `/` 마지막 | §6.9 | **2026-08-10** |
| 10 | **직원 API ALB 등록** | **금지** | §0.2 | **2026-08-10** |
| 11 | **cloudflared 이미지** | digest 핀 (`:latest` 금지) | §16-4 | **2026-08-10** |
| 12 | **JDBC TLS 옵션** | `sslMode=REQUIRED` | Connector/J deprecated | **2026-08-10** |
| 13 | **JWT 발급 주체** | **BFF 단독.** WAS 발급 금지 | §6.5 | **2026-08-10** |
| 14 | **역할 claim** | `role` 단수 문자열 | §6.5 | **2026-08-10** |
| 15 | **환자/직원 JWT TTL** | 30분 / 8시간 | §6.5 | **2026-08-10** |
| 16 | **DB PK 명명** | `patient_id` / `staff_id` 유지 | §6.8 | **2026-08-10** |
| 17 | **직원 활성 컬럼** | `status ENUM` 유지, `ACTIVE`만 로그인 | §6.8 | **2026-08-10** |
| 18 | **`must_change_password`** | `DEFAULT 0` | §6.8 | **2026-08-10** |
| 19 | **예약 상태 표현** | WAS는 표준 enum 반환. 한글 라벨은 각 Web | §6.8 | **2026-08-10** |
| 20 | **X-Actor 검증** | BFF 1차 + WAS 2차 (불일치 403) | §6.6 | **2026-08-10** |
| 21 | **BFF `/readyz`** | WAS에 종속시키지 않는다 | §7.9 | **2026-08-10** |
| 22 | **Access JWT 검증** | Dashboard Protect with Access. BFF 미검사 | §7.10 | **2026-08-10** |
| 23 | **Java / Spring Boot / Gradle** | 25 / 4.1.0 / 9.5.1 | §5.3 | **2026-08-10** |
| 24 | **patient-web 베이스** | `nginx-unprivileged:stable-alpine` (8080·non-root) | §5.3 | **2026-08-10** |
| 25 | **CORS** | 추가하지 않음 (동일 도메인) | §6.9 | **2026-08-10** |
| 26 | **NetworkPolicy** | 백로그 | §17.3 | **2026-08-10** |
| 27 | **공공데이터 적재 방식** | **오프라인 seed 1회.** WAS 런타임 호출 금지 | §7.11 | **2026-08-10** |
| 28 | **ICD 적재 필터 (A안)** | `완전코드구분<>'N' AND 주상병사용구분<>'N'` → 마스터 14,283 / 동의어 37,543 | §6.10 | **2026-08-10** |
| 29 | **ICD 테이블 구조** | `icd_code` + `icd_code_synonym` **2테이블 분리** | §6.8 (코드 중복 6,785종) | **2026-08-10** |
| 30 | **처방 발급 API** | `POST /api/bff/staff/charts` **단일 트랜잭션.** 신규 경로 없음 | §7.12 | **2026-08-10** |
| 31 | **상병명 보관** | `chart.icd_name_snapshot` 발급 시점 복사. 소급 수정 금지 | §6.8 | **2026-08-10** |
| 32 | **DB 숫자 컬럼** | `TINYINT`/`SMALLINT` 미사용. **`INT` 로 통일** | §6.8 (Hibernate JDBC 타입 정합) | **2026-08-11** |
| 33 | **`chart.note` 매핑** | `@Lob` + **`length = 65535`** (MySQL `TEXT`) | §6.8 | **2026-08-11** |
| 34 | **예약 가능 슬롯 기준** | `max(조회일 00:00, now)` — 조회와 생성의 판정 일치 | §6.6 | **2026-08-11** |
| 35 | **로컬 통합 기동** | `docker compose up --build -d --wait` | 구축설명서 §6.2 | **2026-08-11** |
| 36 | **Nimbus JOSE+JWT 버전** | **`10.9.1` 명시 핀.** Boot 4.1 BOM 미관리 | §5.3 | **2026-08-11** |
| 37 | **BFF starter 구성** | `starter-web` + `starter-security` + `starter-validation` + **`starter-restclient`**. `starter-data-jpa` 미포함(§6.5 DB 접근 금지를 의존성으로 강제) | §5.3 | **2026-08-11** |
| 38 | **BFF → WAS HTTP 클라이언트** | **`JdkClientHttpRequestFactory`.** `SimpleClientHttpRequestFactory` 는 401 본문을 삼킨다 | §6.6 | **2026-08-11** |
| 39 | **BFF 아웃바운드 URI** | 쿼리 값은 **URI 템플릿 변수**로만 전달. 문자열 연결·사전 인코딩 금지 | §6.6 | **2026-08-11** |
| 40 | **로그인 실패 카운터** | `REQUIRES_NEW` 별도 트랜잭션(`LoginAttemptService`) | §6.5 | **2026-08-11** |
| 41 | **오류 응답 작성** | `response.reset()` 금지. `trace_id` 는 절대 null 을 내보내지 않는다 | §6.7 | **2026-08-11** |
| 42 | **파드 CPU limits** | WAS·BFF **500m** (1코어 아님). ResourceQuota `limits.cpu: 6` | §11 (quota 소진 실측) | **2026-08-12** |
| 43 | **server-side apply** | `--force-conflicts` 사용. 매니페스트가 단일 권위 | §11 | **2026-08-12** |
| 44 | **CSRF 쿠키 Path** | **`/`** (JS 가 읽어야 한다). `PATIENT_TOKEN` 만 `/api/bff/patient` 로 축소 | §6.5 | **2026-08-12** |

**베이스 이미지 digest 기록란** — 최초 빌드 시 채우고 커밋한다.

| 이미지 | digest |
|---|---|
| `amazoncorretto:25-alpine` | `sha256:________` |
---

## §22. P2 실행 기록 및 교훈 — ✅ v3.2 신설

> **범위: 애플리케이션 구현부터 G2 통과까지.** 인프라(P0·P1)는 §19·§20에 있다.

### 22.1 산출 순서와 실제 소요

| 배치 | 산출물 | 검증 게이트 |
|---|---|---|
| 1 | `db/01~03.sql`, `gen-bcrypt.ps1` | 로컬 MySQL 8.0.46 실행 |
| 1.5 | `convert-icd.ps1`, `04_icd_seed.sql` | D2 (14,283 / 37,543) |
| 2a | WAS 빌드·엔티티·리포지토리 | 컴파일 |
| 2b | WAS 필터·인증·업무·`JpaBootstrapTest` | **W1** |
| 2c | `local/` compose + `verify-was.ps1` | **D3 · W2 (38/38)** |
| 3a | BFF `JwtIssuer` · `TokenResolver` · `SecurityConfig` | JWT 계약 5개 |
| 3b | BFF 컨트롤러 · `GlobalExceptionHandler` | 바인딩 계약 7개 |
| 3c | compose 3단 + `verify-bff.ps1` | **B1 · B2 (45/45)** |
| 4a | `k8s/` 매니페스트 · `deploy.ps1` · `preflight.ps1` | 파드 기동 |
| 4b | `patient-web` · Ingress · `verify-flow1.ps1` | **G2 (24/24 + 브라우저)** |

### 22.2 검증 하네스가 잡지 못한 것 — 가장 비싼 교훈

**`verify-bff.ps1` 45/45 + `verify-flow1.ps1` 22/22 를 통과한 상태에서
브라우저 회원가입이 403 으로 실패했다.**

원인은 CSRF 쿠키의 `Path=/api/bff/patient` 였다.
`document.cookie` 는 **현재 문서 경로**에 해당하는 쿠키만 반환하는데 화면은 `/` 에서
열린다. JS 가 토큰을 영원히 읽지 못한다. PowerShell `CookieContainer` 는 조회 시
경로를 인자로 받으므로 이 결함을 통과시켰다.

| 하네스가 브라우저보다 관대한 지점 | 결과 |
|---|---|
| 쿠키 조회 시 경로를 지정할 수 있다 | Path 결함을 놓친다 |
| `Secure` 속성을 강제하지 않는다 | http 에서도 쿠키가 저장된다 |
| `SameSite` 를 해석하지 않는다 | **아직 미검증 영역** |

> **원칙: 사람이 브라우저로 통과하기 전에는 G2 를 닫지 않는다.**
> 스크립트는 회귀 방지 도구이지 최종 판정자가 아니다.

### 22.3 설계 판단이 실증된 것

| 설계 | 증거 |
|---|---|
| DB 제약이 본선, 앱 체크는 보조 | `slot_taken` · `duplicate_booking` · `duplicate_prescription` · `patient_exists` 4종이 전부 UNIQUE 위반 → 계약 코드 변환으로 동작 |
| 취소 시 NULL 이 되는 생성 컬럼 | 취소 후 동일 슬롯 재예약 성공 |
| 상병명 스냅샷 | 마스터 UPSERT 후에도 `chart.icd_name_snapshot` 이 발급 시점 값 유지 |
| 3중 권한 방어 | BFF 401 → `ActorHeaderFilter` 403 → `ChartService` NURSE 403 |
| 전달수단 바인딩 | 직원 JWT 를 쿠키에 실으면 **서명은 통과하고 바인딩만이 막는다** |
| `X-Actor-*` 제거 | 위조 헤더 주입 → 401 |
| `/readyz` 종속 차단 | BFF `/readyz` 가 WAS 상태를 보지 않아 WAS 재배포 중에도 BFF 가 Ready 유지 |
| `maxUnavailable: 0` | 롤아웃 전 구간에서 정상 파드 ≥ 1 |

### 22.4 반복된 실패 유형

같은 뿌리에서 여러 번 터진 것들이다. 다음 배치에서 먼저 확인한다.

**① PowerShell 5.1 파일 입출력 — 5회**

`utf8NoBOM` 미지원 / BOM 없는 `.ps1` 을 CP949 로 파싱 / `Get-Content -Raw` 가 CP949 로 읽음 /
`Set-Content -Encoding UTF8` 이 BOM 추가 / `.NET` 이 PowerShell 현재 위치를 모름.

> **표준: 파일 치환은 `[System.IO.File]::ReadAllText/WriteAllText` + `Resolve-Path` + `UTF8Encoding($false)`.**
> `.ps1` 자체는 **UTF-8 BOM + CRLF** 로 저장한다.

**② Spring Boot 4 / Security 7 이관 — 4회**

BOM 이 `nimbus-jose-jwt` 미관리 / `RestClient.Builder` 자동 구성이 별도 모듈 /
`AntPathRequestMatcher` 제거 / Jackson 3 에서 `WRITE_DATES_AS_TIMESTAMPS` 이동.

> **Boot 3 관용구를 그대로 옮기면 기동 시점에 터진다.** 표면이 넓은 BFF 에 집중됐다.

**③ 매니페스트 총량 계산 — 1회, 그러나 진단이 가장 어려웠다**

`limits.cpu: 1` × 4파드 = ResourceQuota `limits.cpu: 4` 정확히 소진.
**파드가 생성되지 않아 `describe pod`·`describe rs`·로그·이벤트가 전부 비어 있다.**
`describe resourcequota` 한 줄이 유일한 단서였다.

### 22.5 배포 이력

| 태그 | 대상 | 비고 |
|---|---|---|
| `b631234` | WAS | 최초 배포 |
| `b631234` | BFF | 최초 배포 |
| `b07d408` | WAS · BFF · patient-web | CPU limits 교정 |
| `7b35c0b` | BFF · patient-web | CSRF 쿠키 Path 교정 |
| `cad77bb` | cloudflared | digest 치환. ECR 미경유(퍼블릭 이미지 직접 배포) |

> ECR immutable tag 다. 태그는 git short SHA 이며, 이 표가 이미지와 커밋을 잇는
> 유일한 추적 수단이다. **배포할 때마다 여기에 기록한다.**

### 22.6 G2 시점 미해결 항목

| # | 항목 | 영향 | 처리 |
|---|---|---|---|
| 1 | `SameSite=Lax` 실동작 미검증 | 외부 링크 진입 흐름 | 브라우저 수동 확인 |
| 2 | 콘솔에 초기 401 1회 | 없음. **의도된 동작** | 유지 (§22.7) |
| 3 | `UserDetailsServiceAutoConfiguration` 경고 | 없음 | 명시적 비활성화 검토 |
| 4 | 검증 스크립트 한글 정렬 깨짐 | 로그 오독 위험 | 표시 폭 기준 패딩으로 교체 |
| 5 | RDS 에 검증 데이터 잔존 | 시연 데이터와 혼재 | G3 전 정리 여부 판단 |

### 22.7 G3 실행 기록 — ✅ v3.2 추가

### 산출

| | |
|---|---|
| `k8s/cloudflared/deployment.yaml` | replicas 2, digest 핀 |
| `scripts/verify-flow2.ps1` | 흐름2 검증 29개 |
| `scripts/preflight.ps1` | G3 준비 점검 3개 추가 (14 → 17) |

### 실행 순서 (실제로 통한 순서)

리드(Tunnel·Access 구성 → Service Auth 정책 → Service Token 발급)
→ EKS팀(digest 치환 → `cloudflared-secret` → 배포 → `preflight` 17/17)
→ `verify-flow1.ps1`(차트 미작성 예약 확보) → `verify-flow2.ps1`.

Tunnel 은 4커넥션(icn05·icn06 이중화)으로 등록됐고, cloudflared 파드는 2/2 Running,
Cloudflare 대시보드 HEALTHY 를 확인했다.

### 검증 스크립트 자체 결함 1건 — 인프라는 처음부터 정상이었다

최초 실행에서 2건 FAIL:

```
[FAIL] Service Token 없이 접근 차단        status=403
[FAIL] 잘못된 Service Token → 403         status=403
```

상태코드는 기대값과 정확히 일치했다. 원인은 판정 로직에 `Content-Type` 조건을
같이 걸어둔 것 — **Cloudflare Access 의 차단 응답 자체가 `text/html`(자체 오류
페이지)이다.** 이를 "Policy 가 Allow 일 때의 로그인 폼 신호"와 혼동해 실패로
잘못 판정했다.

`Allow` 오설정이었다면 `302` 또는 `200`(로그인 폼) 이 왔을 것이나, 실제로는
두 경우 모두 **403** 이었다 — **Service Auth 가 처음부터 정확히 동작하고 있었다.**

교정: 판정을 **상태코드만**으로 좁히고, Allow 오탐지는 `302`/`200` 여부를 보는
별도 항목으로 분리했다 (29개로 증가). 재실행 후 인프라 재작업 없이 **29/29**.

> **교훈** — 검증 실패를 발견하면 먼저 "무엇을 기대했는가" 를 의심한다.
> 계약(§7.10)이 요구하는 것은 "브라우저 로그인 흐름으로 새지 않는다" 이지
> "오류 응답이 JSON 이어야 한다" 가 아니다. 후자는 내가 추가한, 근거 없는 조건이었다.

### 확정된 것

| 항목 | 증거 |
|---|---|
| Access Service Auth 정확 설정 | 토큰 없음/오류 → 403, 올바른 토큰 → 401 JSON |
| Tunnel → cloudflared → bff-svc → was-svc → RDS 전 구간 관통 | 로그인·처방 발급 성공 |
| 3역할 로그인 + TTL 8시간 | 전부 PASS |
| 3중 권한 방어 | NURSE 403 / ADMIN_STAFF 404(경로 없음, 403 아님) / **위조 `X-Actor-*` 401** |
| 처방 발급 전 구간 | 201 → 스냅샷 → 409 중복 → 조회 |
| `X-Trace-Id` 연속성 | BFF → WAS 전 구간 |

---

### 22.8 브라우저 콘솔의 초기 401 — 정상이다

`patient-web` 은 페이지 진입 시 `GET /api/bff/patient/appointments` 를 호출해
로그인 상태를 판정한다. 미로그인이면 401 이 오고 가입 화면을 띄운다.

`PATIENT_TOKEN` 은 HttpOnly 라 JS 가 읽을 수 없다. **서버에 물어보는 것이 유일한 방법이다.**
브라우저는 `fetch` 의 4xx 를 콘솔에 자동 출력하며 `catch` 로도 막을 수 없다.

대안을 검토했으나 전부 대가가 더 크다.

| 대안 | 대가 |
|---|---|
| `/auth/me` 신설 | 신규 경로 추가 — §7.12 위반 |
| `localStorage` 플래그 | 서버 상태와 어긋난다 |
| 초기 조회 제거 | 새로고침마다 로그아웃처럼 보인다 |

---

## 베이스 이미지 digest

> ⚠️ 이 표에서 값을 **복사해 쓰지 않는다.** 렌더링된 마크다운 복사는 조용한 절단을
> 일으킨다 (§15, 3회 사고). 기록·대조용이며, 실제 치환은 `docker inspect` 출력을 쓴다.

| 이미지 | digest | 기록일 |
|---|---|---|
| `amazoncorretto:25-alpine` | `sha256:027310590da693629c2cf704d2f87e9359c33ee2f02bcaa777680b2f4b94f4c7` | 2026-08-11 |
| `nginxinc/nginx-unprivileged:1.27-alpine` | `sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0` | 2026-08-12 |
| `cloudflare/cloudflared` | `sha256:________` | ⬜ G3 |

> ✅ **v3.2** — patient-web 베이스는 `stable-alpine` 이 아니라 **`1.27-alpine`** 으로 확정했다.
> 태그가 움직이지 않는 편이 digest 재확인 주기를 예측 가능하게 만든다.

---

## 문서 갱신 규칙

| 상황 | 조치 |
|---|---|
| 구조·버전·표준 변경 | 이 문서를 **먼저** 수정하고 PR |
| 새 트러블슈팅 발견 | §15에 추가 |
| 결정 사항 확정 | **§21 표에 기록** |
| 문서와 코드 불일치 발견 | **문서가 틀린 것.** 즉시 PR |

---

## 프로젝트 완료 요약 — ✅ v3.2

**G1 → G3 뼈대 완성.** DB(§6.8) → WAS(§6.6) → BFF(§6.5) → 환자 Web(§6.9) →
직원 Web 진입점(§7.10) 까지 계약대로 구현·배포·검증됐다.

| 구간 | 검증 |
|---|---|
| DB | 상병코드 14,283 + 동의어 37,543, `app_was` 최소 권한 |
| WAS | `verify-was.ps1` 38/38 |
| BFF | `verify-bff.ps1` 45/45 |
| 흐름1 (환자, HTTPS) | `verify-flow1.ps1` 24/24 + 브라우저 실동작 |
| 흐름2 (직원, Tunnel) | `verify-flow2.ps1` 29/29 |

**범위 밖으로 이관한 것**: OKD Web 구현(프로젝트 기간 제약), §17.3 전체
(NetworkPolicy·mTLS·CI/CD·HPA·관측성·Refresh Token 등).

재개 시 시작점은 §17.3 백로그와 §22 실행 기록이다. 계약(§6)은 이 시점 이후
변경되지 않았으므로 유효하다.

---

## 종료 시

- [ ] `terraform destroy` — 미실행 시 EKS $0.10/h + NAT + RDS가 계속 과금된다
- [ ] destroy 전 `db/` 디렉토리의 DDL·seed가 git에 커밋되어 있는지 확인 (§7.7)

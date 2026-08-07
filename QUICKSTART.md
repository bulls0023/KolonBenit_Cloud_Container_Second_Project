# 담당별 요약 (Quick Reference)

> 상세 기준은 `README.md`. 이 문서는 **본인 섹션만 읽고 바로 착수**하기 위한 요약이다.
> 각 표의 **받을 것 / 넘길 것**이 팀 간 계약이다. 여기서 막히면 상대 담당자에게 즉시 알린다.

## 공통 상수 (전원 암기)

```
프로젝트      hybrid-toy          리전   ap-northeast-2
클러스터      hybrid-toy-eks      NS     app
컨테이너 포트  8080               헬스   /healthz, /readyz
이미지 태그    git short SHA (:latest 금지)
DB            commondb / 3306 / MySQL 8.0
```

```
[외부] Cloudflare → ALB → patient-web → bff → was → RDS
[내부] OKD Pod → CF Access → CF Tunnel → cloudflared → bff → was → RDS
```

---

# 1. 인프라 리드

**한 줄:** 뼈대를 깔고 apply하는 유일한 사람. 나머지 3팀을 언블로킹하는 것이 최우선 임무.

### 순서

| # | 작업 | 비고 |
|---|---|---|
| 1 | **Cloudflare 도메인 등록 + 네임서버 이전** | 전파 최대 24h. **가장 먼저** |
| 2 | 팀원 IAM User 생성 + AccessKey 배포 | 4명 |
| 3 | **§8 블로커 3가지 코드 반영** | 아래 필수 |
| 4 | `backend-bootstrap` apply (최초 1회) | 버킷명 → `envs/dev/backend.tf` |
| 5 | `terraform apply -target=module.ecr` | ~1분. **즉시 EKS팀 공유** |
| 6 | `terraform plan -out=tfplan` → `apply tfplan` | ~25분 |
| 7 | ACM 검증 CNAME → Cloudflare 등록 | **회색 구름(DNS only)** |
| 8 | `kubectl create namespace app` + LB Controller Helm 설치 | Ingress 전제조건 |
| 9 | **G1 선언** — output 전체 공유 | |
| 10 | Cloudflare SSL/TLS = **Full (strict)**, WAF/RateLimit 구성 | |
| 11 | Web 담당에게 ALB DNS 수령 → CNAME 등록 (**주황 구름**) | **G2** |
| 12 | Tunnel 생성 + Access App (**Action = Service Auth**) + Service Token | **G3** |

### apply 전 블로커 3가지 (미처리 시 전 팀 마비)

1. **팀원 EKS 접근 권한** — `access_entries` 추가. 없으면 리드 외 전원 `kubectl` 불가
2. **S3 버킷명** — 부트스트랩과 `backend.tf` 값 일치 (전역 유일)
3. **ECR IMMUTABLE 공지** — `:latest` 푸시 실패함. 변경하려면 apply 전에

### 넘길 것

| 대상 | 항목 | 시점 |
|---|---|---|
| EKS팀 전원 | ECR URL 3개 | apply -target 직후 |
| EKS팀 전원 | 클러스터명, kubeconfig 명령, NS | G1 |
| WAS·DB | RDS 엔드포인트 / 3306 | G1 |
| Web | ACM 인증서 ARN | G1 |
| BFF | Tunnel Token | P3 |
| OKD팀 | 내부 도메인 + Service Token (ID/Secret) | P3 |

### 절대 금지

`backend-bootstrap` 재실행 · tfstate/tfvars 커밋 · Cloudflare를 Terraform으로 이관

### 미결정 (apply 전 확정)

☐ RDS TLS 강제 ☐ Secrets Manager 전환 ☐ ECR 태그 정책

---

# 2. EKS — WAS 담당 ⚠️ 임계 경로 1순위

**한 줄:** BFF·Web 2명이 당신을 기다린다. **가장 먼저 배포를 끝내야 한다.**

### 순서

| # | 작업 | 시점 |
|---|---|---|
| 1 | Dockerfile + `/healthz` `/readyz` 구현 | P0 (AWS 불필요) |
| 2 | 로컬 MySQL로 통합 테스트 | P0 |
| 3 | ECR 푸시 (`--platform linux/amd64`) | ECR 나오면 즉시 |
| 4 | Secret 생성 (DB 자격증명) | G1 후 |
| 5 | Deployment + Service(ClusterIP 8080) 배포 | G1 후 |
| 6 | **DB 커넥션 수립 로그 확인** | |
| 7 | **BFF 담당에게 "was-svc 준비 완료" 통보** | 즉시 |

> 🚨 **DB팀 스키마를 기다리지 마라.** 커넥션 수립만 확인하고 바로 6→7로 간다. 대기하면 BFF·Web이 전부 밀린다.

### 받을 것 / 넘길 것

| 받을 것 | 출처 |
|---|---|
| RDS 엔드포인트 | 인프라 리드 (G1) |
| `app_was` 계정/비밀번호 | DB팀 (P2, 늦어도 됨) |

| 넘길 것 | 대상 |
|---|---|
| `was-svc` 준비 완료 신호 | BFF 담당 |

### 환경변수 (§6.2 계약)

```
DB_HOST / DB_PORT=3306 / DB_NAME=commondb   → ConfigMap
DB_USER=app_was / DB_PASSWORD               → Secret
```

### 검증

```bash
kubectl -n app run tmp --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s http://was-svc.app.svc.cluster.local:8080/healthz
```

### 주의

`admin` 계정 직접 사용 금지 · TLS 강제 적용 시 JDBC에 `useSSL=true&requireSSL=true` 필수

---

# 3. EKS — BFF 담당

**한 줄:** 외부·내부 **두 흐름이 합류하는 지점**. cloudflared도 담당한다.

### 순서

| # | 작업 | 시점 |
|---|---|---|
| 1 | Dockerfile + `/healthz` `/readyz` 구현 | P0 |
| 2 | **OKD팀과 API 스펙 합의** (공통 API 공유 권장) | P0 |
| 3 | ECR 푸시 (`--platform linux/amd64`) | ECR 나오면 즉시 |
| 4 | ConfigMap에 `WAS_BASE_URL` 주입 | WAS 완료 후 |
| 5 | Deployment + Service(ClusterIP 8080) 배포 | |
| 6 | BFF→WAS 프록시 호출 검증 | |
| 7 | **Web 담당에게 "bff-svc 준비 완료" 통보** | 즉시 |
| 8 | **[P3]** cloudflared Secret + Deployment(replicas 2) | Tunnel Token 수령 후 |

### 받을 것 / 넘길 것

| 받을 것 | 출처 |
|---|---|
| `was-svc` 준비 완료 | WAS 담당 |
| Tunnel Token | 인프라 리드 (P3) |

| 넘길 것 | 대상 |
|---|---|
| `bff-svc` 준비 완료 | Web 담당 |
| API 스펙 | OKD팀 |

### 환경변수

```
WAS_BASE_URL=http://was-svc.app.svc.cluster.local:8080   → ConfigMap (하드코딩 금지)
TUNNEL_TOKEN                                              → Secret
```

### cloudflared 요점

- **아웃바운드 전용** — Service·Ingress·인바운드 SG 전부 불필요
- `replicas: 2` — 1개면 파드 재시작 중 내부 흐름 단절
- 검증: 파드 로그 등록 성공 + CF 대시보드 Tunnel **HEALTHY**

---

# 4. EKS — Web 담당

**한 줄:** 외부 흐름의 종착점. **Ingress를 만드는 순간 ALB가 실제로 생성된다.**

### 순서

| # | 작업 | 시점 |
|---|---|---|
| 1 | Dockerfile + `/healthz` `/readyz` 구현 | P0 |
| 2 | ECR 푸시 (`--platform linux/amd64`) | ECR 나오면 즉시 |
| 3 | ConfigMap에 `BFF_BASE_URL` 주입 | BFF 완료 후 |
| 4 | Deployment + Service 배포 | |
| 5 | Web→BFF 호출 검증 | |
| 6 | **Ingress 작성** (ACM ARN, `healthcheck-path: /healthz`) | |
| 7 | ALB DNS명 확보 → **인프라 리드에게 전달** | **G2** |

### 받을 것 / 넘길 것

| 받을 것 | 출처 |
|---|---|
| `bff-svc` 준비 완료 | BFF 담당 |
| ACM 인증서 ARN | 인프라 리드 |

| 넘길 것 | 대상 |
|---|---|
| ALB DNS명 | 인프라 리드 → Cloudflare CNAME |

### Ingress 필수 annotation

```yaml
alb.ingress.kubernetes.io/scheme: internet-facing
alb.ingress.kubernetes.io/target-type: ip
alb.ingress.kubernetes.io/certificate-arn: <ACM_ARN>
alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
alb.ingress.kubernetes.io/healthcheck-path: /healthz
```

```bash
kubectl -n app get ingress patient-web -w   # ADDRESS에 ALB DNS 뜰 때까지 ~3분
```

### 주의

**Target Group unhealthy 영구 지속 = `/healthz` 미구현 또는 경로 불일치.** 최빈 사고 1위

---

# 5. DB 담당

**한 줄:** ⚠️ **로컬 PC에서 RDS 직접 접속 불가.** 접속 경로부터 확인하고 시작한다.

### 접속 방법 — 이것만 쓴다

```bash
kubectl -n app run mysql-cli --rm -it --image=mysql:8.0 --restart=Never -- \
  mysql -h <RDS_ENDPOINT> -u admin -p
```

RDS는 DB 전용 서브넷 + SG(EKS 노드 SG만 허용) 안에 있다. 파드 트래픽이 노드 SG를 경유해 통과한다.
**SG에 개인 IP 임시 허용은 금지** — 격리 설계가 무의미해진다.

### 순서

| # | 작업 | 시점 |
|---|---|---|
| 1 | ERD 설계 | P0 (AWS 불필요) |
| 2 | **DDL 스크립트 작성 → git 커밋** | P0. `skip_final_snapshot=true`라 destroy 시 데이터 소실 |
| 3 | 로컬 MySQL 8.0에서 DDL 검증 | P0 |
| 4 | 마이그레이션 도구 선정 (Flyway/Liquibase) | P0 |
| 5 | 임시 파드로 접속 확인 | G1 후 |
| 6 | `commondb`에 DDL 실행 → **WAS 담당 즉시 통보** | G1 후 |
| 7 | `app_was` 계정 생성 → WAS 담당 전달 | P2 |
| 8 | 시드 데이터, 인덱스 검증(`EXPLAIN`) | P2 |

### 앱 계정 — `admin` 공유 금지

```sql
CREATE USER 'app_was'@'%' IDENTIFIED BY '<강력한 비밀번호>';
GRANT SELECT, INSERT, UPDATE, DELETE ON commondb.* TO 'app_was'@'%';
FLUSH PRIVILEGES;
```

`DROP`/`ALTER`/`CREATE` 권한 부여 금지 — 스키마 변경은 DB팀 전담.
TLS 강제를 적용한 경우에만 `ALTER USER ... REQUIRE SSL;` 추가 (미적용 시 붙이면 WAS 접속 실패).

### 받을 것 / 넘길 것

| 받을 것 | 출처 |
|---|---|
| RDS 엔드포인트, `admin` 비밀번호 | 인프라 리드 (G1) |

| 넘길 것 | 대상 | 시점 |
|---|---|---|
| 스키마 생성 완료 신호 | WAS 담당 | 즉시 |
| `app_was` 계정/비밀번호 | WAS 담당 | P2 |

---

# 6. OKD (온프레미스) 담당

**한 줄:** AWS 계정·자격증명·VPN 전부 불필요. **아웃바운드 HTTPS 호출만** 하면 된다.

### 담당 범위

| ✅ 담당 | Web Pod가 Cloudflare Access 엔드포인트를 HTTPS 호출 |
|---|---|
| ❌ 비담당 | cloudflared 배포(BFF 담당), Tunnel/Access 설정(인프라 리드) |

### 순서

| # | 작업 | 시점 |
|---|---|---|
| 1 | **아웃바운드 443 허용 확인** | **지금 즉시** — 방화벽 승인에 며칠 |
| 2 | 사내 DNS가 공인 도메인 해석하는지 확인 | 지금 |
| 3 | 프록시 존재 / TLS MITM 검사 여부 확인 | 지금 |
| 4 | Pod Egress Policy 제한 여부 확인 | 지금 |
| 5 | **BFF 담당과 API 스펙 합의** | P0 |
| 6 | Service Token을 OpenShift Secret으로 생성 | P3 |
| 7 | Web Pod에서 호출 → **`200 application/json`** 확인 | **G3** |

```bash
curl -sv https://www.cloudflare.com --max-time 10   # 1번 확인
env | grep -i proxy                                  # 3번 확인
```

> ⚠️ **1~4는 인프라 리드의 apply와 무관하게 지금 확인 가능하다.** 가장 먼저 착수.

### 받을 것

| 항목 | 출처 | 비고 |
|---|---|---|
| 내부 흐름 도메인 | 인프라 리드 (P3) | |
| Service Token Client ID / Secret | 인프라 리드 (P3) | 🔒 **Secret은 1회만 표시** |

### 호출 방식

```bash
curl -s https://internal-xxx.<도메인>/api/health \
  -H "CF-Access-Client-Id: <CLIENT_ID>" \
  -H "CF-Access-Client-Secret: <CLIENT_SECRET>"
```

헤더 이름은 **정확히 이대로.** 토큰은 Secret으로 주입, 이미지·코드 하드코딩 금지, 로그 출력 금지.
타임아웃 connect 5s / read 30s, 재시도 2~3회 지수 백오프.

### 🚨 최빈 실패 — HTML/302 응답

```bash
curl -s -o /dev/null -w "%{http_code} %{content_type}\n" <URL> -H "..." -H "..."
```

- `200 application/json` → 정상
- `302` 또는 `text/html` → 아래 순서로 추적

| 원인 | 조치 주체 |
|---|---|
| Access Policy Action이 `Allow` (`Service Auth` 아님) | **인프라 리드** |
| 헤더 이름 오타 / Secret 값 손상 | OKD팀 |

### 프록시 환경

```yaml
- name: HTTPS_PROXY
  value: "http://proxy.internal:3128"
- name: NO_PROXY
  value: "localhost,127.0.0.1,.svc,.cluster.local"
```

TLS MITM 검사 시 사내 CA를 ConfigMap 마운트 + 신뢰 저장소 등록. 미조치 시 `certificate verify failed`.

---

# 전원 공통 — 최빈 사고 5선

| 증상 | 원인 | 조치 |
|---|---|---|
| ACM 영원히 Pending | 검증 CNAME이 주황 구름 | 회색 구름으로 |
| 무한 리다이렉트 루프 | CF SSL 모드 Flexible | Full (strict)로 |
| Target Group unhealthy | `/healthz` 없음/경로 불일치 | 구현 + annotation 확인 |
| OKD가 HTML 수신 | Access Action이 `Allow` | `Service Auth`로 |
| `exec format error` | Apple Silicon ARM 이미지 | `--platform linux/amd64` |

## 금지 사항

리드 외 `terraform apply` · `backend-bootstrap` 재실행 · tfstate/tfvars 커밋 · `:latest` 태그 ·
RDS SG에 개인 IP 허용 · DB 서브넷에 `kubernetes.io/*` 태그 · `admin` 계정 앱 사용 ·
URL 하드코딩 · **뼈대(G3) 완성 전 기능 추가**

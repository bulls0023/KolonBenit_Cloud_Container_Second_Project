# Kuspital — 하이브리드 병원 정보시스템

## 인프라 개요

### 전체 아키텍처

본 프로젝트는 **외부 환자 서비스(AWS EKS)**와 **내부 직원 서비스(온프레미스 OKD)**를 하나의 시스템으로 연동한 하이브리드 아키텍처입니다. 두 환경은 물리적으로 완전히 분리된 네트워크에 있지만, Cloudflare Tunnel을 통해 안전하게 데이터를 주고받습니다.

```
[외부 환자 흐름]                          [내부 직원 흐름]
Browser (환자)                            Browser (직원, 사내망)
    │                                          │
Cloudflare (WAF, Rate Limit, DDoS 방어)    OKD Web Pod (서버사이드 프록시)
    │                                          │
IGW → ALB (TLS 종단)                      Cloudflare Access (Service Auth)
    │                                          │
┌─────────────── AWS VPC (10.0.0.0/16) ──────────────────────┐
│                                                              │
│  Public Subnet(AZ-A/C)  Private Subnet ×2 (AZ-A/C)  DB Subnet(Multi-AZ)
│  ALB, NAT Gateway   →   Amazon EKS Cluster (app)  →  RDS MySQL 8.0
│                          ├─ patient-web (nginx)        Primary(AZ-A)
│                          ├─ bff (Spring Boot)           Standby(AZ-C)
│                          ├─ was (Spring Boot)
│                          └─ cloudflared (Tunnel Client)
└──────────────────────────────────────────────────────────────┘
```

### 네트워크 설계

| 항목 | 값 |
|---|---|
| VPC CIDR | `10.0.0.0/16` |
| Public Subnet (AZ-A/C) | `10.0.1.0/24`, `10.0.11.0/24` — ALB, NAT Gateway |
| Private Subnet — EKS (AZ-A/C) | `10.0.2.0/24`, `10.0.12.0/24` — patient-web, bff, was |
| Database Subnet (Multi-AZ) | `10.0.4.0/24`, `10.0.14.0/24` — RDS MySQL |
| 트래픽 방향 | 외부 사용자(환자) → Cloudflare → ALB → EKS. 내부 사용자(직원) → OKD → Cloudflare Access → Tunnel → EKS 내부 서비스 |

### 컴퓨팅 계층

| 서비스 | 역할 | 스택 |
|---|---|---|
| `patient-web` | 환자용 정적 프론트엔드 + API 리버스 프록시 | nginx (unprivileged) |
| `bff` | 인증·인가, 요청 라우팅, WAS 프록시 (DB 직접 접근 없음) | Spring Boot 4.1.0 (Java 25) |
| `was` | 비즈니스 로직, DB 접근 전담 | Spring Boot 4.1.0 (Java 25) |
| `cloudflared` | 온프레미스-클라우드 아웃바운드 터널 클라이언트 | cloudflared:latest |
| OKD Web Pod | 직원용 React 프론트엔드 + 서버사이드 세션/프록시 | React, Kubernetes(OKD 4.3.7) |

### AWS 공통 서비스

| 서비스 | 용도 |
|---|---|
| Amazon ECR | 컨테이너 이미지 레지스트리 |
| AWS IAM | 권한 관리, OIDC 기반 CI/CD 인증 |
| AWS ACM | ALB TLS 인증서 |
| Amazon CloudWatch Observability | 메트릭·로그·대시보드·알람 |
| AWS Secrets Manager | RDS 마스터 시크릿 관리 |
| Amazon S3 | Terraform 상태(tfstate) 저장 |

### 보안·네트워크 격리 원칙

- **인바운드 리스너 최소화**: OKD ↔ EKS 간 통신은 양방향 모두 Cloudflare로 향하는 **아웃바운드 연결만** 사용. 어느 쪽도 상대방을 향한 인바운드 포트를 열지 않음 (DMZ 구성·네트워크 분리 가이드라인 준수)
- **DB 서브넷 완전 격리**: RDS는 EKS 클러스터 내부에서만 접근 가능, 외부·보안 그룹으로만 접근 허용, Multi-AZ 구성
- **Pod Security 강제**: 임시 작업용 파드를 포함한 모든 파드에 `restricted` PodSecurity 정책 적용 (`runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: ALL`)

### 인프라 코드화

- **Terraform ≥ 1.10** 기반 전체 인프라 코드화 (`.tfstate`는 S3, `.tfvars`는 절대 커밋하지 않음, `.terraform.lock.hcl`은 커밋 — provider 버전 고정)
- **CI/CD**: GitHub Actions → ECR 자동 빌드·푸시 (OIDC 기반, 장기 Access Key를 저장소에 두지 않음) → (선택) EKS Deployment 이미지 갱신

---

## DB 설계 및 보안

### 스키마 구조 — 마스터 5종 / 트랜잭션 4종, 총 10개 테이블

데이터베이스는 "새 행이 거의 안 늘어나는 명단(마스터)"과 "사건이 있을 때마다 계속 쌓이는 기록(트랜잭션)"으로 명확히 구분해 설계했습니다.

#### 마스터 테이블 (5종, 6개 테이블)

| 테이블 | 역할 | 비고 |
|---|---|---|
| `patient_user` | 환자 계정 | API 셀프 가입, 비밀번호 BCrypt 해싱 |
| `staff_user` | 직원 계정 | 셀프 가입 없음, 관리자 발급(seed) 전용, 발급자 추적(`created_by`) |
| `doctor` | 의사 프로필 | `staff_user`와 1:1 |
| `doctor_slot` | 예약 가능 시간대 | 30분 단위, 근무 스케줄 기반 생성 |
| `icd_code` / `icd_code_synonym` | 상병코드 마스터 + 동의어 색인 | 대표 코드 1건 : 동의어 N건 (1:N) — PK 중복 문제로 테이블 분리 |

#### 트랜잭션 테이블 (4종)

| 테이블 | 역할 | 핵심 설계 |
|---|---|---|
| `appointment` | 예약 | 이중 UNIQUE 제약으로 동시성 방어 |
| `chart` | 진료 차트(SOAP) | 예약 1건 : 차트 1건 |
| `prescription` | 처방전 헤더 | 차트 1건 : 처방 0~1건 |
| `prescription_item` | 처방 품목 | 처방전 1건 : 품목 N건 |

### 동시성 방어 — DB 제약이 최종 방어선

애플리케이션의 사전 조회(빈 슬롯 확인)만으로는 동시 요청을 완전히 막을 수 없습니다. 두 환자가 같은 시간대를 정확히 동시에 예약 시도할 경우, 조회 시점엔 둘 다 "비어있음"으로 보일 수 있기 때문입니다.

```sql
UNIQUE KEY uk_appt_active_slot    (active_slot_id)      -- 같은 슬롯 중복 예약 차단
UNIQUE KEY uk_appt_active_patient (active_patient_slot) -- 같은 환자 이중 예약 차단
```

`DataIntegrityViolationException`을 WAS에서 캐치해 "방금 다른 분이 예약했습니다" 형태의 사용자 메시지로 변환. 취소된 예약은 생성 컬럼(`active_slot_id`)이 `NULL`이 되어 유니크 제약에서 자동 제외되므로, 취소 후 같은 슬롯이 다시 예약 가능한 상태로 돌아옵니다.

### 계정·권한 분리 — 최소 권한 원칙

| 계정 | 용도 | 권한 |
|---|---|---|
| `admin` | 스키마 관리 전용 (DDL, GRANT) | 전체 |
| `app_was` | WAS 애플리케이션 전용 | 테이블 단위 화이트리스트 |

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON commondb.patient_user TO 'app_was'@'%';
GRANT SELECT, INSERT, UPDATE ON commondb.doctor_slot TO 'app_was'@'%';   -- DELETE 없음
GRANT SELECT ON commondb.icd_code TO 'app_was'@'%';                      -- 조회만
GRANT SELECT, UPDATE ON commondb.staff_user TO 'app_was'@'%';            -- INSERT/DELETE 없음
```

**`GRANT ... ON commondb.*`(광역 권한)는 사용하지 않습니다.** MySQL은 광역으로 부여한 권한을 테이블 단위로 회수할 수 없어(`ERROR 1147`), 처음부터 테이블 단위로 설계해야 나중에 유연하게 조정할 수 있습니다.

### 저장·전송 암호화

| 구간 | 방식 |
|---|---|
| 비밀번호 저장 | BCrypt 해싱 (`CHAR(60)`), 평문 저장 컬럼 없음 |
| DB 연결 구간 | TLS 강제(`REQUIRE SSL`), `Ssl_cipher` 값으로 실제 적용 검증 |
| RDS 마스터 비밀번호 | AWS Secrets Manager로 이전, 코드/Terraform 변수에 평문 없음 |

### 계정 보호 — 무차별 대입 방어

```sql
failed_login_count INT NOT NULL DEFAULT 0
locked_until DATETIME NULL
```

5회 로그인 실패 시 30분 계정 잠금, 성공 시 초기화.

### 네트워크 격리

- RDS는 **Database Subnet(Private, Multi-AZ)**에 배치, 외부 인터넷에서 직접 도달 불가
- 로컬 PC에서 직접 접속 시도는 물리적으로 경로가 없어 실패 — 반드시 클러스터 내부 임시 파드를 경유해야만 접속 가능
- 임시 접속 파드도 `restricted` PodSecurity 정책 적용 (root 실행 차단, 권한 상승 차단)

### 개인정보 접근 통제 — IDOR 방지

다른 사용자 소유 리소스에 잘못된 ID로 접근 시, `403`(권한 없음)이 아닌 `404`(존재하지 않음)로 응답합니다. 403은 "그 리소스가 실제로 존재한다"는 정보 자체를 노출하므로, 존재 여부를 숨기는 쪽을 택했습니다.

### 상병코드(ICD) 오프라인 적재

건강보험심사평가원이 공공데이터포털을 통해 제공하는 KCD(한국표준질병사인분류) 상병마스터 데이터를 사용했습니다.

- **적재 방식**: WAS가 공공데이터 API를 실시간 호출하는 대신, **사전에 오프라인으로 DB에 적재**. 외부 포털 장애가 서비스 가용성에 영향을 주지 않도록 설계
- **적재 규모**: `icd_code` 14,283건, `icd_code_synonym`(동의어) 37,543건
- **테이블 분리 이유**: 하나의 상병기호에 명칭이 여러 개 달린 경우가 존재(예: `E1140` 하나에 동의어 60건). `code`를 PK로 잡으면 동의어 전체를 한 테이블에 넣을 수 없어 대표 1건(`icd_code`) + 동의어 N건(`icd_code_synonym`) 구조로 분리
- **검증**: 적재 후 `COUNT(*)` 대조 + 특정 코드(`E1140`) 동의어 건수·한글 명칭 정상 출력 확인
- **권한**: `app_was`는 이 두 테이블에 **SELECT만** 가능 — 런타임에 참조 마스터가 오염되지 않도록 권한으로 강제

### 실제 병원정보시스템 보안 가이드라인 매핑

프로젝트 착수 전 실제 병원정보시스템 보안 가이드라인을 채택하고, DB 담당 조치를 가이드라인 조항과 1:1로 매핑·검증했습니다.

| 조치 | 대응 가이드라인 조항 |
|---|---|
| 네트워크 격리 (RDS Private 서브넷 + 임시 파드 경유) | 1.2.3, 1.3.1, 3.3.1 |
| 계정·권한 분리 (admin/app_was, 테이블별 GRANT) | 1.3.3, 2.1.1, 2.1.2, 2.2.2 |
| 사용자 인증·계정 관리 (BCrypt 검증, 잠금, 발급자 추적) | 2.1.3, 2.1.4 |
| 암호화 (저장 BCrypt + 전송 TLS) | 2.1.6, 2.2.3, 2.3.2 |
| 개인정보 접근 통제 (IDOR 방지) | 3.4 |

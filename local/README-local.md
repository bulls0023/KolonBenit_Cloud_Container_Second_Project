# 로컬 통합 검증 (배치 2c + 3c)

계약: README v3.1 §6.1 / §6.8 / §13.2 · 구축설명서 §6.2

## 이 단계에서 처음 검증되는 것

| 항목 | 이전까지 |
|---|---|
| **엔티티 ↔ `01_schema.sql` 정합 (`ddl-auto: validate`)** | H2 가 엔티티에서 스키마를 생성해 자동으로 맞았다. **한 번도 검증된 적 없다** |
| MySQL ENUM / TEXT / 생성 컬럼 매핑 | 미검증 |
| `sslMode=REQUIRED` 실제 동작 | 미검증 |
| `app_was` 최소 권한으로 앱이 도는지 | 미검증 |
| API 계약 (인증·403·409·snake_case) | 미검증 |

## 구성

```
verify-bff  ->  bff (18081)  ->  was (18080)  ->  mysql (13306)
verify-was  ------------------>  was
```

`was` 의 호스트 포트는 **검증·디버깅 전용**이다. EKS 에서 WAS 는 ClusterIP 로만
노출되며 외부에서 도달할 수 없다 (§7.2).

## 실행

```powershell
cd local
.\prepare.ps1
docker compose up --build -d --wait
```

`--wait` 없이 `-d` 만 쓰면 **기동 완료 전에 반환한다.** 검증 스크립트가
전 항목 `status=-1` 로 떨어지고, 애플리케이션 결함으로 오진하게 된다.

```powershell
.\verify-was.ps1      # WAS 직접 검증 (36개)
.\verify-bff.ps1      # BFF 경유 검증 (45개)
```

## 정리

```powershell
docker compose down -v
```

> **`-v` 필수.** MySQL 초기화 스크립트는 **빈 볼륨에서만** 실행된다.
> 볼륨을 남기고 재실행하면 `01~04.sql` 이 돌지 않아 "왜 테이블이 없지" 상태가 된다.

## 로컬 테스트 계정

`doc_kim` / `doc_lee` / `nur_park` / `adm_choi` — 비밀번호 `Local!Hospital2026`

환자는 `verify-was.ps1` 이 매 실행마다 새로 가입시킨다.

## 게이트

| 게이트 | 조건 |
|---|---|
| **D3** | `/readyz` (18080) → `{"status":"ok","db":"up"}` |
| **W2** | `verify-was.ps1` → PASS 36 / FAIL 0 |
| **B1** | `/readyz` (18081) → `{"status":"ok"}` |
| **B2** | `verify-bff.ps1` → PASS 45 / FAIL 0 |

## verify-bff 에서 처음 검증되는 것

| 항목 | 계약 |
|---|---|
| 외부 `X-Actor-*` 제거 | §6.6 위조 방어 1번 원칙 |
| 전달수단 ↔ actor_type 바인딩 | §6.5 — 직원 토큰을 쿠키로 보내면 401 |
| 환자 쿠키 속성 | HttpOnly / Path=/api/bff/patient |
| 응답 JSON 에 토큰 미포함 | §6.5 |
| CSRF | 환자 경로만 적용, 직원 Bearer 면제 |
| WAS 4xx 통과 전달 | §6.6 — 상태·본문 그대로 |
| trace_id 연속성 | §6.7 |

## 예상 실패 지점

| 증상 | 원인 | 조치 |
|---|---|---|
| WAS 가 `Schema-validation` 으로 기동 실패 | 엔티티 ↔ DDL 불일치. **`chart.note` 의 `@Lob` ↔ `TEXT` 가 1순위 후보** | 오류 전문 공유. `ddl-auto: none` 은 임시 우회일 뿐 해결이 아니다 |
| `Access denied for user 'app_was'` | `REQUIRE SSL` 계정에 비TLS 접속 | JDBC `sslMode=REQUIRED` 확인 |
| `SELECT command denied` | `02_grants.sql` 에 테이블 GRANT 누락 | 해당 테이블 추가 후 `down -v` → 재기동 |
| mysql 헬스체크가 계속 starting | `04_icd_seed.sql` 적재 중 | 최대 5분. `docker compose logs mysql` 로 진행 확인 |
| WAS 가 mysql 보다 먼저 떠서 죽음 | `depends_on: condition` 누락 | 이 compose 에는 이미 걸려 있다 |
| BFF 기동 실패 `JWT_SIGNING_KEY` | `.env` 에 키 없음 | `.\prepare.ps1` 재실행 (없으면 자동 보충) |
| 쿠키가 저장되지 않음 | `COOKIE_SECURE=true` + http | `.env` 의 `COOKIE_SECURE=false` 확인 |
| 검증 전 항목 `status=-1` | 기동 전에 스크립트 실행 | `--wait` 사용 |

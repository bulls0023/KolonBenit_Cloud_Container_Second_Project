-- =====================================================================
-- Hybrid Toy Project — 02_grants.sql
-- 계약   : README v3.1 §12.3 / §13.2 / §16-7
-- 실행자 : admin
-- 선행   : 01_schema.sql  (테이블이 존재해야 테이블 단위 GRANT 가 가능하다)
-- =====================================================================
--
-- ⚠️ 이 파일은 git 에 커밋된다. **비밀번호를 직접 적지 않는다.**
--    `__APP_WAS_PASSWORD__` 자리표시자를 실행 직전에 치환한다 (아래 참조).
--
--    # PowerShell — 치환본은 임시 파일로만 만들고 즉시 삭제한다
--    $pw  = Read-Host "app_was password" -AsSecureString
--    $pt  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
--             [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw))
--    (Get-Content .\02_grants.sql -Raw).Replace('__APP_WAS_PASSWORD__', $pt) |
--      Set-Content .\_02_grants.local.sql -Encoding utf8NoBOM
--    # ... 실행 후 ...
--    Remove-Item .\_02_grants.local.sql -Force
--
--    `_02_grants.local.sql` 는 .gitignore 대상이다 (README §16-3).
--
-- =====================================================================
--
-- ▣ 왜 `GRANT ... ON commondb.*` 를 쓰지 않는가  ★ 중요
--
--    MySQL 은 **DB 단위로 부여한 권한을 테이블 단위로 회수할 수 없다.**
--
--      GRANT  SELECT,INSERT,UPDATE,DELETE ON commondb.*         TO app_was;
--      REVOKE INSERT,UPDATE,DELETE        ON commondb.icd_code  FROM app_was;
--      → ERROR 1147: There is no such grant defined for user ...
--
--    `partial_revokes=ON` 을 켜도 동일하다. 이 변수는 전역→DB 범위에만 적용된다.
--    따라서 **테이블 단위로 명시 부여**한다. 화이트리스트가 되므로 보안상으로도 낫다.
--
--    ⚠️ 부작용: 테이블을 새로 추가하면 이 파일에 GRANT 를 **반드시 추가**해야 한다.
--       누락 시 WAS 에서 `SELECT command denied to user 'app_was'` 가 발생한다.
--
-- =====================================================================

USE commondb;


-- ---------------------------------------------------------------------
-- 1. 앱 전용 계정 생성
-- ---------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'app_was'@'%' IDENTIFIED BY '__APP_WAS_PASSWORD__';

-- 이미 존재하는 경우에도 비밀번호를 확정한다 (재실행 시 정합)
ALTER USER 'app_was'@'%' IDENTIFIED BY '__APP_WAS_PASSWORD__';

-- TLS 강제. README §13.2 `require_secure_transport` 와 이중 방어를 이룬다.
ALTER USER 'app_was'@'%' REQUIRE SSL;


-- ---------------------------------------------------------------------
-- 2. 업무 테이블 — 읽기·쓰기
-- ---------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON commondb.patient_user      TO 'app_was'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON commondb.appointment       TO 'app_was'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON commondb.chart             TO 'app_was'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON commondb.prescription      TO 'app_was'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON commondb.prescription_item TO 'app_was'@'%';


-- ---------------------------------------------------------------------
-- 3. 직원 계정 — 읽기 + 잠금 카운터 갱신만
--    직원 계정은 seed 로만 생성한다 (README §6.8). INSERT / DELETE 를 주지 않는다.
--    UPDATE 는 failed_login_count / locked_until 갱신에 필요하다.
-- ---------------------------------------------------------------------
GRANT SELECT, UPDATE ON commondb.staff_user TO 'app_was'@'%';


-- ---------------------------------------------------------------------
-- 4. 진료 자원 마스터 — 삭제 불가
--    ADMIN_STAFF 의 슬롯 관리 API 를 위해 INSERT/UPDATE 는 남긴다.
--    DELETE 는 예약이 걸린 슬롯을 지울 수 있으므로 부여하지 않는다.
-- ---------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON commondb.doctor      TO 'app_was'@'%';
GRANT SELECT, INSERT, UPDATE ON commondb.doctor_slot TO 'app_was'@'%';


-- ---------------------------------------------------------------------
-- 5. 상병코드 마스터 — 읽기 전용  ★ v3.1
--    적재는 04_icd_seed.sql (admin) 이 담당한다.
--    WAS 가 이 테이블을 변경할 수 있으면 §7.11 의 "런타임 적재 금지"가
--    코드 리뷰 하나에만 의존하게 된다. 권한으로 막는다.
-- ---------------------------------------------------------------------
GRANT SELECT ON commondb.icd_code         TO 'app_was'@'%';
GRANT SELECT ON commondb.icd_code_synonym TO 'app_was'@'%';


-- ---------------------------------------------------------------------
-- 6. 부여하지 않는 권한 — 명시적으로 남긴다
--    CREATE / DROP / ALTER / INDEX  : 스키마 변경은 DB팀 전담 (README §16-7)
--    FILE / PROCESS / SUPER         : 불필요
--    GRANT OPTION                   : 권한 재위임 차단
-- ---------------------------------------------------------------------

FLUSH PRIVILEGES;


-- =====================================================================
-- 검증
-- =====================================================================
-- SHOW GRANTS FOR 'app_was'@'%';
--
-- 기대 결과 (순서 무관)
--   GRANT USAGE ON *.* TO `app_was`@`%` ... REQUIRE SSL     ← REQUIRE SSL 필수
--   GRANT SELECT, INSERT, UPDATE, DELETE ON `commondb`.`patient_user` ...
--   GRANT SELECT, INSERT, UPDATE, DELETE ON `commondb`.`appointment` ...
--   GRANT SELECT, INSERT, UPDATE, DELETE ON `commondb`.`chart` ...
--   GRANT SELECT, INSERT, UPDATE, DELETE ON `commondb`.`prescription` ...
--   GRANT SELECT, INSERT, UPDATE, DELETE ON `commondb`.`prescription_item` ...
--   GRANT SELECT, UPDATE          ON `commondb`.`staff_user` ...
--   GRANT SELECT, INSERT, UPDATE  ON `commondb`.`doctor` ...
--   GRANT SELECT, INSERT, UPDATE  ON `commondb`.`doctor_slot` ...
--   GRANT SELECT                  ON `commondb`.`icd_code` ...
--   GRANT SELECT                  ON `commondb`.`icd_code_synonym` ...
--
-- ⚠️ `GRANT ... ON commondb.*` 줄이 보이면 이전 실행의 잔재다. 회수한다:
--    REVOKE ALL PRIVILEGES ON commondb.* FROM 'app_was'@'%';
--    이후 이 파일을 다시 실행한다.
--
-- app_was 로 재접속하여 TLS 확인 (README §12.1)
--   SELECT 1;
--   SHOW STATUS LIKE 'Ssl_cipher';      -- 값이 비어 있으면 TLS 미적용
-- =====================================================================

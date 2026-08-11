-- =====================================================================
-- Hybrid Toy Project — 03_seed.sql
-- 계약   : README v3.1 §6.8
-- 실행자 : admin
-- 선행   : 01_schema.sql
-- 내용   : 직원 4명(3역할) / 의사 2명 / 진료 슬롯 7일치
-- =====================================================================
--
-- ⚠️ 환자는 seed 하지 않는다. API 로 가입한다 (README §6.8).
-- ⚠️ 상병코드는 04_icd_seed.sql 이 담당한다. 이 파일에 없다.
--
-- =====================================================================
-- ▣ BCrypt 해시 — 실행 전 반드시 치환한다
--
--    평문 비밀번호를 이 파일에 적지 않는다. 채팅·PR·스크린샷에도 남기지 않는다
--    (구축설명서 §3.1-4).
--
--    1) 해시 생성
--         .\tools\gen-bcrypt.ps1
--    2) 아래 4개 자리표시자를 생성된 `$2b$...` 60자 문자열로 치환
--         __HASH_DOC_KIM__  __HASH_DOC_LEE__  __HASH_NUR_PARK__  __HASH_ADM_CHOI__
--    3) 치환본(`_03_seed.local.sql`)으로 실행 후 즉시 삭제
--
--    ⚠️ 치환 후 문자열이 `$2b$` 로 시작하고 **정확히 60자**인지 확인한다.
--       CHAR(60) 컬럼이므로 짧으면 뒤가 공백 패딩되어 BCrypt 검증이 조용히 실패한다.
--
-- ▣ 재실행 안전성
--    전 구문이 `INSERT IGNORE` 다. 재실행해도 중복이 생기지 않는다.
--    ⚠️ 그 대신 **기존 행을 갱신하지 않는다.** 해시를 바꾸려면 UPDATE 를 직접 쓴다.
-- =====================================================================

USE commondb;

SET NAMES utf8mb4;


-- ---------------------------------------------------------------------
-- 1. 직원 계정 — 3역할 전부 포함
--    must_change_password = 0  (README §21-18. DEFAULT 1 아님)
--    status = 'ACTIVE'         (WAS 는 ACTIVE 만 로그인 허용)
-- ---------------------------------------------------------------------
INSERT IGNORE INTO staff_user
  (login_id,   password_hash,       name,     role,          department, status,   must_change_password)
VALUES
  ('doc_kim',  '__HASH_DOC_KIM__',  '김의사', 'DOCTOR',      '내과',     'ACTIVE', 0),
  ('doc_lee',  '__HASH_DOC_LEE__',  '이의사', 'DOCTOR',      '정형외과', 'ACTIVE', 0),
  ('nur_park', '__HASH_NUR_PARK__', '박간호', 'NURSE',       '내과',     'ACTIVE', 0),
  ('adm_choi', '__HASH_ADM_CHOI__', '최원무', 'ADMIN_STAFF', '원무과',   'ACTIVE', 0);


-- ---------------------------------------------------------------------
-- 2. 의사 프로필
--    staff_id 를 상수로 박지 않는다. AUTO_INCREMENT 값은 실행 이력에 따라 달라진다.
--    login_id 로 조회해서 연결한다.
-- ---------------------------------------------------------------------
INSERT IGNORE INTO doctor (staff_id, department, specialty, room_no, is_active)
SELECT s.staff_id, s.department, v.specialty, v.room_no, 1
  FROM staff_user s
  JOIN (
        SELECT 'doc_kim' AS login_id, '당뇨·내분비' AS specialty, '201' AS room_no
        UNION ALL
        SELECT 'doc_lee',             '척추·관절',                '305'
       ) v ON v.login_id = s.login_id
 WHERE s.role = 'DOCTOR';


-- ---------------------------------------------------------------------
-- 3. 진료 슬롯 — 오늘부터 7일, 30분 단위
--
--    09:00~11:30 (6칸) / 점심 12:00~13:00 휴진 / 13:00~17:30 (10칸) = 1일 16칸
--    16칸 × 7일 × 의사 2명 = 224행
--
--    날짜를 상수로 박으면 며칠 뒤 데모에서 "예약 가능 슬롯 0건"이 된다.
--    CURDATE() 기준으로 생성한다. 재실행하면 그날 기준으로 다시 채워진다.
--    (uk_slot_doctor_time 이 중복을 막으므로 INSERT IGNORE 로 안전하다)
-- ---------------------------------------------------------------------
INSERT IGNORE INTO doctor_slot (doctor_id, slot_at, is_open)
WITH RECURSIVE seq (i) AS (
  SELECT 0
  UNION ALL
  SELECT i + 1 FROM seq WHERE i < 111          -- 16칸 × 7일 - 1
)
SELECT d.doctor_id,
       TIMESTAMP(
         DATE_ADD(CURDATE(), INTERVAL FLOOR(seq.i / 16) DAY),
         SEC_TO_TIME(
           IF(seq.i % 16 < 6,
              9 * 3600 + (seq.i % 16)       * 1800,   -- 09:00 ~ 11:30
             13 * 3600 + (seq.i % 16 - 6)   * 1800)   -- 13:00 ~ 17:30
         )
       ) AS slot_at,
       1
  FROM seq
 CROSS JOIN doctor d
 WHERE d.is_active = 1;


-- =====================================================================
-- 검증 — 실행 직후 아래를 돌린다
-- =====================================================================
-- SELECT login_id, name, role, status, must_change_password
--   FROM staff_user ORDER BY staff_id;
--   → 4행. must_change_password 전부 0
--
-- SELECT COUNT(*) FROM doctor;                       -- 2
-- SELECT COUNT(*) FROM doctor_slot;                  -- 224
-- SELECT MIN(slot_at), MAX(slot_at) FROM doctor_slot;
--   → 오늘 09:00 ~ 6일 후 17:30
--
-- 해시 치환 누락 검사 (0 이어야 한다)
-- SELECT COUNT(*) AS unreplaced FROM staff_user WHERE password_hash LIKE '\_\_HASH%';
--
-- 해시 길이 검사 (전부 60 이어야 한다)
-- SELECT login_id, LENGTH(password_hash) AS len, LEFT(password_hash, 4) AS prefix
--   FROM staff_user;
--
-- 평문 유출 검사 — git 커밋 전 필수
--   PowerShell:  Select-String -Path .\03_seed.sql -Pattern '\$2[aby]\$'
--   → 매칭이 나오면 해시가 파일에 박힌 것이다. 커밋하지 않는다.
-- =====================================================================

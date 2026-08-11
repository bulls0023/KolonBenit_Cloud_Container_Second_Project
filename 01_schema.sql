-- =====================================================================
-- Hybrid Toy Project — 01_schema.sql
-- 대상   : MySQL 8.0 (RDS `commondb`)
-- 계약   : README v3.1 §6.8 (DB 계약) / §6.10 (ICD 적재)
-- 실행자 : admin  (app_was 아님 — app_was 에는 DDL 권한이 없다)
-- 실행순 : 01_schema.sql → 02_grants.sql → 03_seed.sql → 04_icd_seed.sql
-- =====================================================================
--
-- ▣ 재실행 안전성
--   전 구문이 `CREATE TABLE IF NOT EXISTS` 다. 재실행해도 데이터가 지워지지 않는다.
--   ⚠️ 그 대신, 이미 존재하는 테이블의 정의가 이 파일과 달라도 **조용히 통과한다.**
--      스키마를 수정했다면 아래 초기화 블록을 수동으로 실행한 뒤 다시 돌린다.
--
-- ▣ 전체 초기화 (개발 환경 전용 — 데이터 전량 소실)
--   아래 주석을 해제해서 실행한다. FK 역순이므로 순서를 바꾸지 않는다.
--
--   SET FOREIGN_KEY_CHECKS = 0;
--   DROP TABLE IF EXISTS prescription_item, prescription, chart,
--                        appointment, doctor_slot, doctor,
--                        icd_code_synonym, icd_code,
--                        staff_user, patient_user;
--   SET FOREIGN_KEY_CHECKS = 1;
--
-- =====================================================================

CREATE DATABASE IF NOT EXISTS commondb
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE commondb;

SET NAMES utf8mb4;


-- =====================================================================
-- 1. 계정 계층
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1.1 patient_user — 환자. API 로 가입한다 (README §6.8)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS patient_user (
  patient_id          BIGINT       NOT NULL AUTO_INCREMENT,
  login_id            VARCHAR(50)  NOT NULL,
  password_hash       CHAR(60)     NOT NULL             COMMENT 'BCrypt only. 평문 컬럼 없음',
  name                VARCHAR(50)  NOT NULL,
  birth_date          DATE         NOT NULL,
  phone               VARCHAR(20)      NULL,
  failed_login_count  TINYINT      NOT NULL DEFAULT 0,
  locked_until        DATETIME         NULL             COMMENT 'NULL = 잠금 아님',
  created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                   ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (patient_id),
  UNIQUE KEY uk_patient_login_id (login_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='환자 계정. 가입은 POST /internal/patient/auth/register';

-- ---------------------------------------------------------------------
-- 1.2 staff_user — 직원. 셀프 가입 없음. seed 로만 생성 (README §6.8)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staff_user (
  staff_id              BIGINT       NOT NULL AUTO_INCREMENT,
  login_id              VARCHAR(50)  NOT NULL,
  password_hash         CHAR(60)     NOT NULL,
  name                  VARCHAR(50)  NOT NULL,
  role                  ENUM('DOCTOR','NURSE','ADMIN_STAFF') NOT NULL
                                     COMMENT 'PATIENT 는 patient_user 계층에서 부여. 여기 없음',
  department            VARCHAR(50)      NULL,
  status                ENUM('ACTIVE','INACTIVE','SUSPENDED') NOT NULL DEFAULT 'ACTIVE'
                                     COMMENT 'WAS 는 ACTIVE 만 로그인 허용',
  must_change_password  TINYINT(1)   NOT NULL DEFAULT 0
                                     COMMENT '⚠️ DEFAULT 0 확정 (README §21-18). 1 아님',
  failed_login_count    TINYINT      NOT NULL DEFAULT 0,
  locked_until          DATETIME         NULL,
  created_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                     ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (staff_id),
  UNIQUE KEY uk_staff_login_id (login_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='직원 계정. 3역할 ENUM';


-- =====================================================================
-- 2. 진료 자원 계층
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2.1 doctor — GET /api/bff/patient/doctors 의 원본
--     staff_user 와 1:1. 의사만 진료 슬롯을 가진다.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS doctor (
  doctor_id    BIGINT       NOT NULL AUTO_INCREMENT,
  staff_id     BIGINT       NOT NULL,
  department   VARCHAR(50)  NOT NULL             COMMENT '진료과. 예: 내과',
  specialty    VARCHAR(100)     NULL,
  room_no      VARCHAR(20)      NULL,
  is_active    TINYINT(1)   NOT NULL DEFAULT 1,
  created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (doctor_id),
  UNIQUE KEY uk_doctor_staff (staff_id),
  KEY idx_doctor_dept (department),
  CONSTRAINT fk_doctor_staff FOREIGN KEY (staff_id)
    REFERENCES staff_user (staff_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='의사 프로필. staff_user.role=DOCTOR 인 행만 참조한다 (DB 로는 강제 불가 — WAS 검증)';

-- ---------------------------------------------------------------------
-- 2.2 doctor_slot — GET /api/bff/patient/slots 의 원본
--     예약 가능 시간대를 미리 생성해 둔다. 슬롯 없이는 예약이 불가능하다.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS doctor_slot (
  slot_id     BIGINT     NOT NULL AUTO_INCREMENT,
  doctor_id   BIGINT     NOT NULL,
  slot_at     DATETIME   NOT NULL   COMMENT 'Asia/Seoul. 30분 단위',
  is_open     TINYINT(1) NOT NULL DEFAULT 1
                         COMMENT '0 = 진료 불가(휴진). 예약 여부와 무관',
  created_at  DATETIME   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (slot_id),
  UNIQUE KEY uk_slot_doctor_time (doctor_id, slot_at),
  KEY idx_slot_at (slot_at),
  CONSTRAINT fk_slot_doctor FOREIGN KEY (doctor_id)
    REFERENCES doctor (doctor_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='진료 슬롯 마스터';


-- =====================================================================
-- 3. 예약 계층
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1 appointment
--
--   ★ 동시성 방어 (README §6.8 — 애플리케이션 체크는 보조, DB 제약이 본선)
--
--     uk_appt_active_slot     : 같은 슬롯 중복 예약 차단  → 409 slot_taken
--     uk_appt_active_patient  : 같은 환자 같은 시각 중복 → 409 duplicate_booking
--
--   ★ 취소 후 재예약 문제
--     status 컬럼에 그냥 UNIQUE 를 걸면 "취소된 예약"이 슬롯을 영구 점유한다.
--     MySQL 은 부분 인덱스(partial index)를 지원하지 않으므로,
--     **취소 시 NULL 이 되는 생성 컬럼**에 UNIQUE 를 건다.
--     UNIQUE 인덱스는 NULL 을 중복으로 보지 않는다 — 이것이 유일하게 동작하는 방법이다.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS appointment (
  appointment_id  BIGINT       NOT NULL AUTO_INCREMENT,
  visit_no        VARCHAR(32)  NOT NULL   COMMENT '접수번호. 예 V20260810-0007. WAS 생성',
  patient_id      BIGINT       NOT NULL,
  doctor_id       BIGINT       NOT NULL,
  slot_id         BIGINT       NOT NULL,
  slot_at         DATETIME     NOT NULL   COMMENT 'doctor_slot.slot_at 사본. 조회·중복판정용',
  status          ENUM('booked','cancelled','done') NOT NULL DEFAULT 'booked'
                               COMMENT '⚠️ DB 원본값은 소문자. WAS 가 BOOKED 로 변환 (README §6.8)',
  symptom         VARCHAR(500)     NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP,

  -- 취소되면 NULL → UNIQUE 제약에서 제외된다
  active_slot_id      BIGINT
    GENERATED ALWAYS AS (IF(status = 'cancelled', NULL, slot_id)) STORED,
  active_patient_slot VARCHAR(64)
    GENERATED ALWAYS AS (IF(status = 'cancelled', NULL,
                            CONCAT(patient_id, '#', slot_at))) STORED,

  PRIMARY KEY (appointment_id),
  UNIQUE KEY uk_appt_visit_no       (visit_no),
  UNIQUE KEY uk_appt_active_slot    (active_slot_id),
  UNIQUE KEY uk_appt_active_patient (active_patient_slot),
  KEY idx_appt_patient        (patient_id, slot_at),
  KEY idx_appt_doctor_slot_at (doctor_id, slot_at),
  KEY idx_appt_slot_at_status (slot_at, status),

  CONSTRAINT fk_appt_patient FOREIGN KEY (patient_id)
    REFERENCES patient_user (patient_id) ON DELETE RESTRICT,
  CONSTRAINT fk_appt_doctor  FOREIGN KEY (doctor_id)
    REFERENCES doctor (doctor_id) ON DELETE RESTRICT,
  CONSTRAINT fk_appt_slot    FOREIGN KEY (slot_id)
    REFERENCES doctor_slot (slot_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='예약. 동시성 최종 방어선은 uk_appt_active_slot';


-- =====================================================================
-- 4. 상병코드 마스터 — ✅ v3.1 (README §6.8 / §6.10)
--    ⚠️ 참조 전용. app_was 에는 SELECT 권한만 부여한다 (02_grants.sql)
--    ⚠️ 적재는 04_icd_seed.sql. 이 파일은 구조만 만든다.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4.1 icd_code — 고유 상병기호 14,283건. 대표명 1건씩
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS icd_code (
  code                VARCHAR(6)   NOT NULL   COMMENT 'KCD 상병기호. 원본 최대 6자',
  name_kr             VARCHAR(200) NOT NULL   COMMENT '대표 한글명. 원본 최대 170자',
  name_en             VARCHAR(255)     NULL   COMMENT '대표 영문명. 원본 최대 223자',
  gender_restriction  CHAR(1)          NULL   COMMENT '원본 성별구분. 보유 1,069종',
  age_min             TINYINT UNSIGNED NULL,
  age_max             TINYINT UNSIGNED NULL,
  infectious_class    VARCHAR(8)       NULL   COMMENT '법정감염병 등급. 보유 486종',
  oriental_medicine   VARCHAR(16)      NULL   COMMENT '양·한방 구분. 한방 전용 151종',
  PRIMARY KEY (code),
  KEY idx_icd_code_name (name_kr(32))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='상병코드 마스터. 참조 전용';

-- ---------------------------------------------------------------------
-- 4.2 icd_code_synonym — 명칭 레코드 37,543건
--
--   ★ 왜 테이블을 분리하는가
--     원본은 한 상병기호에 명칭이 여러 건 달린 **동의어 색인**이다.
--     E1140 하나에 60건이 존재한다 (중복 코드 6,785종).
--     단일 테이블에 전량 INSERT 하면 PRIMARY KEY 위반으로 적재가 실패한다.
--     검색은 이 테이블만 조회하면 되므로 UNION 이 필요 없다 (대표명도 여기 포함).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS icd_code_synonym (
  synonym_id  BIGINT       NOT NULL AUTO_INCREMENT,
  code        VARCHAR(6)   NOT NULL,
  name_kr     VARCHAR(200) NOT NULL,
  name_en     VARCHAR(255)     NULL,
  PRIMARY KEY (synonym_id),
  KEY idx_icd_syn_code (code),
  KEY idx_icd_syn_name (name_kr(32)),
  CONSTRAINT fk_icd_syn_code FOREIGN KEY (code)
    REFERENCES icd_code (code) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='상병코드 동의어 색인. GET /staff/icd-codes 검색 대상';


-- =====================================================================
-- 5. 진료·처방 계층 — ✅ v3.1 (README §6.8)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5.1 chart — 예약 1건당 차트 1건
--
--   ★ uk_chart_visit_no 가 처방 중복 발급의 최종 방어선이다.
--     → 409 duplicate_prescription 의 판정 근거 (README §6.6)
--     WAS 는 사전 SELECT 로 판정하지 않는다. DB 제약 위반을 잡아서 변환한다.
--
--   ★ icd_name_snapshot
--     KCD 는 연 1~2회 개정된다. 마스터를 조인해서 명칭을 보여주면
--     과거 처방전의 상병명이 **소급 변경**된다 — 의료 기록으로서 무효다.
--     발급 시점 명칭을 복사 보관한다. 소급 수정 금지 (README §16-21).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chart (
  chart_id          BIGINT       NOT NULL AUTO_INCREMENT,
  visit_no          VARCHAR(32)  NOT NULL,
  patient_id        BIGINT       NOT NULL   COMMENT 'appointment 에서 파생. 요청 본문 값 아님',
  doctor_staff_id   BIGINT       NOT NULL   COMMENT '작성자. X-Actor-Id 에서 파생',
  icd_code          VARCHAR(6)   NOT NULL,
  icd_name_snapshot VARCHAR(200) NOT NULL   COMMENT '발급 시점 명칭 사본. 소급 수정 금지',
  chief_complaint   VARCHAR(500)     NULL,
  note              TEXT             NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (chart_id),
  UNIQUE KEY uk_chart_visit_no (visit_no),
  KEY idx_chart_patient (patient_id, created_at),
  KEY idx_chart_doctor  (doctor_staff_id, created_at),
  KEY idx_chart_icd     (icd_code),
  CONSTRAINT fk_chart_visit FOREIGN KEY (visit_no)
    REFERENCES appointment (visit_no) ON DELETE RESTRICT,
  CONSTRAINT fk_chart_patient FOREIGN KEY (patient_id)
    REFERENCES patient_user (patient_id) ON DELETE RESTRICT,
  CONSTRAINT fk_chart_doctor FOREIGN KEY (doctor_staff_id)
    REFERENCES staff_user (staff_id) ON DELETE RESTRICT,
  CONSTRAINT fk_chart_icd FOREIGN KEY (icd_code)
    REFERENCES icd_code (code) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='진료 차트. 예약 1건당 1건';

-- ---------------------------------------------------------------------
-- 5.2 prescription — 차트 1건당 처방 최대 1건
--     처방 없는 차트가 정상이므로 0..1 이다.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS prescription (
  prescription_id     BIGINT   NOT NULL AUTO_INCREMENT,
  chart_id            BIGINT   NOT NULL,
  patient_id          BIGINT   NOT NULL   COMMENT 'chart 에서 파생',
  issued_by_staff_id  BIGINT   NOT NULL,
  issued_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (prescription_id),
  UNIQUE KEY uk_prescription_chart (chart_id),
  KEY idx_prescription_patient (patient_id, issued_at),
  CONSTRAINT fk_prescription_chart FOREIGN KEY (chart_id)
    REFERENCES chart (chart_id) ON DELETE CASCADE,
  CONSTRAINT fk_prescription_patient FOREIGN KEY (patient_id)
    REFERENCES patient_user (patient_id) ON DELETE RESTRICT,
  CONSTRAINT fk_prescription_staff FOREIGN KEY (issued_by_staff_id)
    REFERENCES staff_user (staff_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='처방전 헤더';

-- ---------------------------------------------------------------------
-- 5.3 prescription_item — 약품 항목 1..N
--     drug_name 은 이번 단계에서 자유 텍스트다.
--     의약품 표준코드 연동은 백로그 (README §17.3)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS prescription_item (
  item_id          BIGINT       NOT NULL AUTO_INCREMENT,
  prescription_id  BIGINT       NOT NULL,
  drug_name        VARCHAR(200) NOT NULL,
  dosage           VARCHAR(50)  NOT NULL   COMMENT '1회 투여량. 예 1정',
  frequency        VARCHAR(50)  NOT NULL   COMMENT '예 1일 2회',
  duration_days    SMALLINT UNSIGNED NOT NULL,
  line_no          SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (item_id),
  KEY idx_item_prescription (prescription_id, line_no),
  CONSTRAINT fk_item_prescription FOREIGN KEY (prescription_id)
    REFERENCES prescription (prescription_id) ON DELETE CASCADE,
  CONSTRAINT ck_item_duration CHECK (duration_days BETWEEN 1 AND 365)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='처방 약품 항목';


-- =====================================================================
-- 검증 — 실행 직후 아래를 돌린다
-- =====================================================================
-- SELECT COUNT(*) AS tables_created
--   FROM information_schema.tables
--  WHERE table_schema = 'commondb';                       -- 10
--
-- SELECT table_name, table_collation
--   FROM information_schema.tables
--  WHERE table_schema = 'commondb';                       -- 전부 utf8mb4_0900_ai_ci
--
-- SHOW CREATE TABLE appointment\G                         -- 생성 컬럼 2개 + UNIQUE 3개
-- =====================================================================

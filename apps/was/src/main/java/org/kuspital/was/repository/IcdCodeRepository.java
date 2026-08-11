package org.kuspital.was.repository;

import org.kuspital.was.domain.IcdCode;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 상병코드 마스터 - 읽기 전용.
 *
 * ⚠️ save() / delete() 를 호출하면 런타임에 권한 오류가 난다.
 *    app_was 에는 SELECT 권한만 부여되어 있다 (README §12.3).
 *    JpaRepository 가 쓰기 메서드를 상속하지만 사용하지 않는다.
 */
public interface IcdCodeRepository extends JpaRepository<IcdCode, String> {
}

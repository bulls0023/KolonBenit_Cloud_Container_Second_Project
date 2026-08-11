package org.kuspital.was.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

/**
 * BCrypt 인코더.
 *
 * [주의] spring-boot-starter-security 를 넣지 않았다. crypto 모듈만 쓴다.
 *   WAS 에는 인증 필터 체인이 없다. JWT 를 발급하지도, 검증하지도 않는다
 *   (README §16-12 / §21-13). 인증·인가는 BFF 가 담당하고,
 *   WAS 는 X-Actor-* 헤더의 2차 검증만 수행한다 (ActorHeaderFilter, 배치 2b).
 *
 * [코스트] db/tools/gen-bcrypt.ps1 이 코스트 10 으로 seed 해시를 만든다.
 *   검증은 해시에 박힌 코스트를 따르므로 여기 값과 달라도 동작은 한다.
 */
@Configuration
public class PasswordEncoderConfig {

    private static final int BCRYPT_COST = 10;

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(BCRYPT_COST);
    }
}

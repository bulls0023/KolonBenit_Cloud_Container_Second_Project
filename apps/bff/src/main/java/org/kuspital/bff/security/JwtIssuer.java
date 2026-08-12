package org.kuspital.bff.security;

import com.nimbusds.jose.*;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jose.crypto.MACVerifier;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import org.kuspital.bff.config.AppProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;

/**
 * JWT 발급·검증. README v3.1 §6.5
 *
 * [단독 지점] 프로젝트 전체에서 JWT 를 만드는 곳은 여기뿐이다.
 *   WAS 의 JWT 발급은 전면 금지되어 있다 (§16-12 / §21-13).
 *
 * [규격]
 *   알고리즘  HS256
 *   claim     sub, actor_type, role, iss, aud, iat, exp
 *   역할       role 단수 문자열. roles 배열 금지
 *   TTL       환자 30분 / 직원 8시간
 *   금지 claim 이름·생년월일·전화번호·진단·처방·비밀번호
 *
 * [미채택] Refresh Token, 키 회전, 폐기 목록 - 전부 백로그 (§6.5)
 */
@Component
public class JwtIssuer {

    private static final Logger log = LoggerFactory.getLogger(JwtIssuer.class);

    private static final String CLAIM_ACTOR_TYPE = "actor_type";
    private static final String CLAIM_ROLE = "role";

    private final AppProperties.Jwt props;
    private final JWSSigner signer;
    private final JWSVerifier verifier;

    public JwtIssuer(AppProperties.Jwt props) {
        this.props = props;

        byte[] key = props.signingKey().getBytes(StandardCharsets.UTF_8);

        // HS256 은 256비트(32바이트) 이상을 요구한다.
        // Nimbus 가 어차피 거부하지만, 메시지를 명확히 하기 위해 먼저 잡는다.
        if (key.length < 32) {
            throw new IllegalStateException(
                    "JWT_SIGNING_KEY 가 " + key.length + "바이트다. HS256 은 32바이트 이상을 요구한다.");
        }

        try {
            this.signer = new MACSigner(key);
            this.verifier = new MACVerifier(key);
        } catch (JOSEException e) {
            throw new IllegalStateException("JWT 서명기 초기화 실패", e);
        }
    }

    // -----------------------------------------------------------------
    // 발급
    // -----------------------------------------------------------------

    public String issuePatient(Long patientId) {
        return issue(patientId, ActorType.PATIENT, Role.PATIENT,
                Duration.ofMinutes(props.patientTtlMinutes()));
    }

    public String issueStaff(Long staffId, Role role) {
        if (role == null || role.actorType() != ActorType.STAFF) {
            throw new IllegalArgumentException("직원 역할이 아니다: " + role);
        }
        return issue(staffId, ActorType.STAFF, role,
                Duration.ofHours(props.staffTtlHours()));
    }

    private String issue(Long subject, ActorType actorType, Role role, Duration ttl) {

        Instant now = Instant.now();

        JWTClaimsSet claims = new JWTClaimsSet.Builder()
                .subject(String.valueOf(subject))
                .issuer(props.issuer())
                .audience(props.audience())
                .issueTime(Date.from(now))
                .expirationTime(Date.from(now.plus(ttl)))
                .claim(CLAIM_ACTOR_TYPE, actorType.name())
                // role 은 단수 문자열이다. roles 배열을 쓰지 않는다 (§6.5).
                .claim(CLAIM_ROLE, role.name())
                .build();

        SignedJWT jwt = new SignedJWT(
                new JWSHeader.Builder(JWSAlgorithm.HS256).type(JOSEObjectType.JWT).build(),
                claims);

        try {
            jwt.sign(signer);
        } catch (JOSEException e) {
            throw new IllegalStateException("JWT 서명 실패", e);
        }

        return jwt.serialize();
    }

    // -----------------------------------------------------------------
    // 검증
    // -----------------------------------------------------------------

    /**
     * 토큰을 검증해 신원을 만든다. 실패 시 null 을 반환한다.
     *
     * ⚠️ 실패 사유를 호출부에 알리지 않는다. 만료·위조·역할 미상을 구분해
     *    응답하면 공격자에게 정보를 준다. 전부 401 unauthorized 다 (§6.5).
     *    사유는 로그로만 남긴다.
     *
     * 검증 순서: 서명 → iss → aud → exp → actor_type → role
     * 전달수단 바인딩은 여기서 하지 않는다. TokenResolver 가 담당한다.
     */
    public AuthenticatedActor verify(String token) {

        if (token == null || token.isBlank()) {
            return null;
        }

        try {
            SignedJWT jwt = SignedJWT.parse(token);

            if (!jwt.verify(verifier)) {
                log.debug("jwt rejected: signature");
                return null;
            }

            JWTClaimsSet claims = jwt.getJWTClaimsSet();

            if (!props.issuer().equals(claims.getIssuer())) {
                log.debug("jwt rejected: issuer");
                return null;
            }
            if (claims.getAudience() == null || !claims.getAudience().contains(props.audience())) {
                log.debug("jwt rejected: audience");
                return null;
            }

            Date exp = claims.getExpirationTime();
            if (exp == null || exp.toInstant().isBefore(Instant.now())) {
                log.debug("jwt rejected: expired");
                return null;
            }

            ActorType actorType;
            try {
                actorType = ActorType.valueOf(String.valueOf(claims.getClaim(CLAIM_ACTOR_TYPE)));
            } catch (IllegalArgumentException | NullPointerException e) {
                log.debug("jwt rejected: actor_type");
                return null;
            }

            Role role = Role.parse(String.valueOf(claims.getClaim(CLAIM_ROLE)));
            if (role == null) {
                log.debug("jwt rejected: unknown role");
                return null;
            }

            // role 과 actor_type 의 정합. 토큰 안에서 서로 모순되면 거부한다.
            if (role.actorType() != actorType) {
                log.debug("jwt rejected: role/actor_type mismatch");
                return null;
            }

            Long id;
            try {
                id = Long.valueOf(claims.getSubject());
            } catch (NumberFormatException | NullPointerException e) {
                log.debug("jwt rejected: subject");
                return null;
            }

            return new AuthenticatedActor(id, actorType, role);

        } catch (Exception e) {
            // 파싱 실패 등. 토큰 내용을 로그에 남기지 않는다.
            log.debug("jwt rejected: parse ({})", e.getClass().getSimpleName());
            return null;
        }
    }
}

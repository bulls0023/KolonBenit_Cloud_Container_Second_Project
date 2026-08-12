package org.kuspital.bff.client;

import org.kuspital.bff.config.AppProperties;
import org.kuspital.bff.error.UpstreamException;
import org.kuspital.bff.filter.TraceIdFilter;
import org.kuspital.bff.security.AuthenticatedActor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;

import java.nio.charset.StandardCharsets;
import java.time.Duration;

/**
 * WAS 호출. README v3.1 §6.6
 *
 * [호출 정책]
 *   connect timeout          2초
 *   read timeout             5초
 *   자동 Retry               없음
 *   WAS 400/401/404/409/423  계약된 상태·본문 그대로 전달
 *   WAS 500 / 연결 실패 / 타임아웃  503 upstream_unavailable 로 변환
 *
 * [Retry 를 넣지 않는 이유] 인증 POST 가 위험하다.
 *   회원가입 재시도는 중복 가입을, 로그인 재시도는 실패 카운트를 조기에
 *   5회로 올려 계정을 잠근다. 멱등하지 않은 요청에 자동 재시도는 사고다.
 *
 * [두 가지 반환 형태]
 *   String 업무 API 용. WAS 응답 JSON 을 그대로 통과시킨다.
 *          BFF 가 DTO 를 다시 정의하면 WAS 와 두 곳에서 관리하게 되어 어긋난다.
 *   타입    인증 API 용. JWT 발급에 actor_id / role 이 필요하므로 파싱한다.
 *
 * [RestClient.Builder 주입] 정적 RestClient.builder() 를 쓰지 않는다.
 *   Boot 가 구성한 빌더를 받아야 애플리케이션의 메시지 컨버터가 적용된다.
 *   정적 빌더는 기본 컨버터를 쓰므로 SNAKE_CASE 설정이 반영되지 않아
 *   actor_id -> actorId 매핑이 조용히 실패한다.
 */
@Component
public class WasClient {

    private static final Logger log = LoggerFactory.getLogger(WasClient.class);

    private final RestClient restClient;

    public WasClient(RestClient.Builder builder, AppProperties.Was props) {

        // ⚠️ SimpleClientHttpRequestFactory(HttpURLConnection) 를 쓰지 않는다.
        //    JDK 의 HttpURLConnection 은 401 응답을 인증 협상 대상으로 보고
        //    에러 스트림을 소비해 버린다. 그 결과 WAS 의 401 본문이 사라져
        //    BFF 가 Content-Length: 0 으로 응답한다 (실측 확인).
        //    409 / 400 은 정상 통과하므로 원인을 찾기 매우 어렵다.
        //    JDK HttpClient 기반 팩토리는 상태코드를 그대로 다룬다.
        java.net.http.HttpClient httpClient = java.net.http.HttpClient.newBuilder()
                .connectTimeout(Duration.ofMillis(props.connectTimeoutMs()))
                // 리다이렉트를 따라가지 않는다. 내부 호출에 리다이렉트는 계약에 없다.
                .followRedirects(java.net.http.HttpClient.Redirect.NEVER)
                .build();

        JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory(httpClient);
        factory.setReadTimeout(Duration.ofMillis(props.readTimeoutMs()));

        this.restClient = builder
                .baseUrl(props.baseUrl())
                .requestFactory(factory)
                .build();
    }

    // -----------------------------------------------------------------
    // 인증 API - 신원 헤더를 보내지 않는다 (README §6.6-6)
    // -----------------------------------------------------------------

    public <T> T postAuth(String path, Object body, Class<T> type) {
        return exchange(HttpMethod.POST, path, body, null, type);
    }

    // -----------------------------------------------------------------
    // 업무 API - 신원 헤더를 새로 만들어 보낸다
    // -----------------------------------------------------------------

    /**
     * ⚠️ 쿼리 값은 반드시 URI 템플릿 변수로 넘긴다.
     *    <pre>get("/path?q={q}", actor, q)</pre>
     *    문자열을 직접 인코딩해 이어붙이면 RestClient 가 한 번 더 인코딩해
     *    '%' 가 '%25' 가 된다. 한글 검색어가 조용히 0건이 된다 (실측).
     */
    public String get(String path, AuthenticatedActor actor, Object... uriVars) {
        return exchange(HttpMethod.GET, path, null, actor, String.class, uriVars);
    }

    public String post(String path, Object body, AuthenticatedActor actor, Object... uriVars) {
        return exchange(HttpMethod.POST, path, body, actor, String.class, uriVars);
    }

    public String patch(String path, Object body, AuthenticatedActor actor, Object... uriVars) {
        return exchange(HttpMethod.PATCH, path, body, actor, String.class, uriVars);
    }

    // -----------------------------------------------------------------

    private <T> T exchange(HttpMethod method, String path, Object body,
                           AuthenticatedActor actor, Class<T> type, Object... uriVars) {

        String traceId = MDC.get(TraceIdFilter.MDC_KEY);

        try {
            RestClient.RequestBodySpec spec = restClient
                    .method(method)
                    .uri(path, uriVars)
                    .accept(MediaType.APPLICATION_JSON);

            if (traceId != null) {
                spec = spec.header(TraceIdFilter.HEADER, traceId);
            }

            // 신원 헤더는 여기서만 만들어진다. 외부가 보낸 값은
            // InboundActorHeaderStripFilter 가 이미 제거했다.
            if (actor != null) {
                spec = spec.header("X-Actor-Type", actor.actorType().name())
                           .header("X-Actor-Id", String.valueOf(actor.id()))
                           .header("X-Actor-Role", actor.role().name());
            }

            if (body != null) {
                spec.contentType(MediaType.APPLICATION_JSON).body(body);
            }

            return spec.retrieve()
                    .onStatus(HttpStatusCode::isError, (req, res) -> {

                        int status = res.getStatusCode().value();
                        byte[] raw = res.getBody().readAllBytes();

                        // 5xx 는 WAS 내부 오류다. 계약 오류가 아니므로 503 으로 바꾼다.
                        if (status >= 500) {
                            log.error("WAS 5xx: {} {} status={}", method, path, status);
                            throw new UpstreamException(-1, null);
                        }

                        // 4xx 는 계약된 오류다. 상태·본문 그대로 올린다.
                        throw new UpstreamException(status,
                                new String(raw, StandardCharsets.UTF_8));
                    })
                    .body(type);

        } catch (UpstreamException e) {
            throw e;
        } catch (ResourceAccessException e) {
            // 연결 실패 / 타임아웃
            log.error("WAS 연결 실패: {} {} ({})", method, path, e.getClass().getSimpleName());
            throw new UpstreamException(-1, null);
        } catch (Exception e) {
            log.error("WAS 호출 오류: {} {}", method, path, e);
            throw new UpstreamException(-1, null);
        }
    }
}

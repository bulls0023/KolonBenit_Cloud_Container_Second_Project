package org.kuspital.bff.error;

/**
 * WAS 가 계약된 오류를 돌려준 경우. 상태·본문을 그대로 전달한다 (§6.6).
 *
 * ⚠️ BFF 가 WAS 의 오류 본문을 다시 만들지 않는다.
 *    재구성하면 두 곳에서 메시지를 관리하게 되어 반드시 어긋난다.
 */
public class UpstreamException extends RuntimeException {

    private final int status;
    private final String body;

    public UpstreamException(int status, String body) {
        super("upstream error " + status);
        this.status = status;
        this.body = body;
    }

    public int status() { return status; }
    public String body() { return body; }
}

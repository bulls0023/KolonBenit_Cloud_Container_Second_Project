// src/api/client.ts
// 공통 API 클라이언트 — DEV-GUIDELINE §2.4/2.5, 최종채택안v1 §3.1/§5, 인프라리드 검토 반영

const BASE_URL = "/api/bff/patient";
const REQUEST_TIMEOUT_MS = 30_000;

export class ApiError extends Error {
  status: number;
  error: string;
  traceId?: string;

  constructor(status: number, error: string, message: string, traceId?: string) {
    super(message);
    this.status = status;
    this.error = error;
    this.traceId = traceId;
    this.name = "ApiError";
  }
}

interface RequestOptions extends Omit<RequestInit, "body"> {
  body?: unknown;
}

// XSRF-TOKEN 쿠키 값을 읽어온다 (최종채택안v1 §3.1 — X-XSRF-TOKEN 헤더 요구)
function getXsrfToken(): string | null {
  const match = document.cookie.match(/(?:^|;\s*)XSRF-TOKEN=([^;]*)/);
  return match ? decodeURIComponent(match[1]) : null;
}

const STATE_CHANGING_METHODS = new Set(["POST", "PATCH", "PUT", "DELETE"]);

async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  const method = (options.method ?? "GET").toUpperCase();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options.headers as Record<string, string>),
  };

  // CSRF — 상태 변경 요청에만 부착 (최종채택안v1 §3.1)
  if (STATE_CHANGING_METHODS.has(method)) {
    const xsrfToken = getXsrfToken();
    if (xsrfToken) headers["X-XSRF-TOKEN"] = xsrfToken;
  }

  try {
    const res = await fetch(`${BASE_URL}${path}`, {
      ...options,
      credentials: "include",
      headers,
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (res.status === 401) {
      window.location.href = "/login";
      throw new ApiError(401, "unauthorized", "로그인이 필요합니다.");
    }

    // ALB/Cloudflare 5xx는 HTML로 온다 — JSON 파싱 시도 전에 Content-Type 확인
    // (인프라 리드 검토 §B-2 공지: "앱 JSON 계약과 무관, Content-Type 검증 필수")
    const contentType = res.headers.get("content-type") ?? "";
    if (!contentType.includes("application/json")) {
      throw new ApiError(
        res.status,
        "upstream_unavailable",
        "일시적으로 서비스에 연결할 수 없습니다. 잠시 후 다시 시도해주세요."
      );
    }

    const text = await res.text();
    const data = text ? JSON.parse(text) : null;

    if (!res.ok) {
      const err = data as { error?: string; message?: string; trace_id?: string } | null;
      throw new ApiError(
        res.status,
        err?.error ?? "internal_error",
        err?.message ?? "요청 처리 중 오류가 발생했습니다.",
        err?.trace_id
      );
    }

    return data as T;
  } catch (e) {
    clearTimeout(timeoutId);

    if (e instanceof ApiError) throw e;

    if (e instanceof DOMException && e.name === "AbortError") {
      throw new ApiError(0, "timeout", "요청 시간이 초과되었습니다. 다시 시도해주세요.");
    }

    throw new ApiError(0, "network_error", "네트워크 연결을 확인해주세요.");
  }
}

export const apiClient = {
  get: <T>(path: string) => request<T>(path, { method: "GET" }),
  post: <T>(path: string, body?: unknown) => request<T>(path, { method: "POST", body }),
  patch: <T>(path: string, body?: unknown) => request<T>(path, { method: "PATCH", body }),
};
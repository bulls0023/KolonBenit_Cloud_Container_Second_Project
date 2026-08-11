package org.kuspital.was.biz;

import org.kuspital.was.domain.IcdCode;
import org.kuspital.was.error.ApiException;
import org.kuspital.was.error.ErrorCode;
import org.kuspital.was.repository.IcdCodeSynonymRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * 상병코드 검색. README §6.6 / §6.10
 *
 * 동의어 테이블을 조회하고 대표명을 반환한다.
 * 검색어에 걸린 동의어가 아니라 공식 분류명을 보여줘야 한다.
 *
 * ⚠️ 읽기 전용이다. app_was 에 icd_* 쓰기 권한이 없다 (README §12.3).
 * ⚠️ 공공데이터포털을 호출하지 않는다 (README §16-19).
 */
@Service
public class IcdSearchService {

    private final IcdCodeSynonymRepository synonymRepository;
    private final int minQueryLength;
    private final int maxResults;

    public IcdSearchService(IcdCodeSynonymRepository synonymRepository,
                            @Value("${app.icd.min-query-length}") int minQueryLength,
                            @Value("${app.icd.max-results}") int maxResults) {
        this.synonymRepository = synonymRepository;
        this.minQueryLength = minQueryLength;
        this.maxResults = maxResults;
    }

    @Transactional(readOnly = true)
    public List<BizDtos.IcdCodeResponse> search(String query) {

        String q = query == null ? "" : query.trim();

        if (q.length() < minQueryLength) {
            throw ApiException.of(ErrorCode.VALIDATION_ERROR,
                    "검색어는 " + minQueryLength + "자 이상 입력해주세요.");
        }

        List<IcdCode> found = synonymRepository.search(q, PageRequest.of(0, maxResults));

        return found.stream()
                .map(c -> new BizDtos.IcdCodeResponse(
                        c.getCode(), c.getNameKr(), c.getNameEn(), c.getInfectiousClass()))
                .toList();
    }
}

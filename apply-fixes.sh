#!/bin/bash
# 파일: apply-fixes.sh
# 목적: 모든 수정사항을 순차적으로 적용하는 마스터 스크립트

set -e

PROJECT_DIR="/Users/leesg/Documents/work_ops/automation-system"
SCRIPT_DIR="$(dirname "$0")"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/iteasy-ops-dev/automation-system-v3-fixes/main"

echo "🚀 통합 자동화 시스템 v3.1 수정사항 적용 시작"
echo "=============================================="

# 현재 시간 기록
START_TIME=$(date)
echo "시작 시간: $START_TIME"

# 1. 사전 준비 작업
echo ""
echo "📋 Phase 1: 사전 준비 작업"
echo "-------------------------"

# 프로젝트 디렉토리 확인
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ 프로젝트 디렉토리를 찾을 수 없습니다: $PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"
echo "✅ 프로젝트 디렉토리 확인: $PROJECT_DIR"

# GitHub 스크립트 다운로드
echo "📥 GitHub에서 수정 스크립트 다운로드..."
mkdir -p scripts/fixes
cd scripts/fixes

# 스크립트 파일들 다운로드
SCRIPTS=(
    "fix-prisma-connection.sh"
    "update-n8n-workflow.sh"
    "end-to-end-test.sh"
)

for script in "${SCRIPTS[@]}"; do
    echo "  📥 $script 다운로드 중..."
    curl -s -L "$GITHUB_RAW_BASE/$script" -o "$script"
    chmod +x "$script"
    
    if [ -f "$script" ]; then
        echo "  ✅ $script 다운로드 완료"
    else
        echo "  ❌ $script 다운로드 실패"
        exit 1
    fi
done

# 2. 현재 상태 백업
echo ""
echo "💾 Phase 2: 현재 상태 백업"
echo "------------------------"

# 백업 디렉토리 생성
BACKUP_DIR="$PROJECT_DIR/backups/fixes-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "📦 현재 상태 백업 중..."
cd "$PROJECT_DIR"

# PostgreSQL 백업
echo "  🗄️ PostgreSQL 백업..."
docker exec automation-postgres pg_dump -U postgres -d automation > "$BACKUP_DIR/postgres-backup.sql"

# n8n 워크플로우 백업
echo "  🔄 n8n 워크플로우 백업..."
N8N_API_KEY="n8n_api_0953a966a0548abd7c3c1a8769e6976036b2dc3430d0de254799876277c00066b4c85bda8723f94d"
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "http://localhost:5678/api/v1/workflows/IjJX9tJR4IPL76oa" > "$BACKUP_DIR/workflow-backup.json"

echo "✅ 백업 완료: $BACKUP_DIR"

# 3. Prisma 연결 문제 해결
echo ""
echo "🔧 Phase 3: Prisma 데이터베이스 연결 문제 해결"
echo "----------------------------------------"

cd "$PROJECT_DIR/scripts/fixes"
echo "🔄 Prisma 연결 수정 스크립트 실행..."

if ./fix-prisma-connection.sh; then
    echo "✅ Prisma 연결 문제 해결 완료"
else
    echo "❌ Prisma 연결 문제 해결 실패"
    echo "백업에서 복원하려면 다음을 실행하세요:"
    echo "docker exec -i automation-postgres psql -U postgres -d automation < $BACKUP_DIR/postgres-backup.sql"
    exit 1
fi

# 4. n8n 워크플로우 SSH 인증 수정
echo ""
echo "🔐 Phase 4: n8n 워크플로우 SSH 인증 수정"
echo "--------------------------------------"

echo "🔄 n8n 워크플로우 업데이트 스크립트 실행..."

if ./update-n8n-workflow.sh; then
    echo "✅ n8n 워크플로우 SSH 인증 수정 완료"
else
    echo "❌ n8n 워크플로우 업데이트 실패"
    echo "백업에서 복원하려면 다음을 실행하세요:"
    echo "curl -X PUT -H \"X-N8N-API-KEY: $N8N_API_KEY\" \\"
    echo "  -H \"Content-Type: application/json\" \\"
    echo "  -d @$BACKUP_DIR/workflow-backup.json \\"
    echo "  http://localhost:5678/api/v1/workflows/IjJX9tJR4IPL76oa"
    exit 1
fi

# 5. 시스템 안정화 대기
echo ""
echo "⏳ Phase 5: 시스템 안정화 대기"
echo "----------------------------"

echo "🔄 모든 서비스 재시작 중..."
docker-compose restart

echo "⏳ 시스템 안정화 대기 (60초)..."
for i in {1..60}; do
    echo -n "."
    sleep 1
done
echo ""

# 핵심 서비스 준비 상태 확인
echo "🔍 핵심 서비스 준비 상태 확인..."
SERVICES=(
    "http://localhost:8101/api/v1/devices/health:Device Service"
    "http://localhost:8201/api/v1/mcp/health:MCP Service"
    "http://localhost:8301/api/v1/llm/health:LLM Service"
    "http://localhost:8401/api/v1/workflows/health:Workflow Service"
    "http://localhost:5678/api/v1/workflows:n8n API"
)

ALL_READY=true
for service in "${SERVICES[@]}"; do
    IFS=':' read -r url name <<< "$service"
    
    echo "  🔍 $name 확인 중..."
    for attempt in {1..15}; do
        if curl -s "$url" > /dev/null 2>&1; then
            echo "  ✅ $name 준비 완료"
            break
        fi
        
        if [ $attempt -eq 15 ]; then
            echo "  ❌ $name 준비 실패"
            ALL_READY=false
        else
            echo "    ⏳ 대기 중... ($attempt/15)"
            sleep 2
        fi
    done
done

if [ "$ALL_READY" = false ]; then
    echo "⚠️ 일부 서비스가 준비되지 않았습니다. 계속 진행합니다..."
fi

# 6. 통합 테스트 실행
echo ""
echo "🧪 Phase 6: 통합 테스트 실행"
echo "---------------------------"

echo "🚀 엔드투엔드 테스트 실행..."

cd "$PROJECT_DIR/scripts/fixes"
if ./end-to-end-test.sh; then
    echo "✅ 모든 테스트 통과!"
    TEST_RESULT="SUCCESS"
else
    TEST_EXIT_CODE=$?
    if [ $TEST_EXIT_CODE -eq 1 ]; then
        echo "⚠️ 대부분의 테스트 통과. 일부 기능에 문제가 있을 수 있습니다."
        TEST_RESULT="PARTIAL_SUCCESS"
    else
        echo "❌ 다수의 테스트 실패. 시스템에 심각한 문제가 있습니다."
        TEST_RESULT="FAILURE"
    fi
fi

# 7. 최종 결과 및 사용법 안내
echo ""
echo "🎯 Phase 7: 최종 결과 및 사용법 안내"
echo "================================"

END_TIME=$(date)
DURATION=$(($(date -d "$END_TIME" +%s) - $(date -d "$START_TIME" +%s)))

echo "완료 시간: $END_TIME"
echo "소요 시간: ${DURATION}초"
echo ""

case $TEST_RESULT in
    "SUCCESS")
        echo "🎉 수정 완료! 시스템이 완전히 작동합니다."
        echo ""
        echo "📋 이제 다음과 같이 사용할 수 있습니다:"
        echo ""
        echo "1. 웹 인터페이스:"
        echo "   http://localhost:3001"
        echo ""
        echo "2. API를 통한 직접 요청:"
        echo "   curl -X POST http://localhost:8401/api/v1/workflows/chat \\"
        echo "     -H \"Content-Type: application/json\" \\"
        echo "     -d '{\"sessionId\": \"test\", \"message\": \"1번 서버의 메모리 사용량을 알려줘\"}'"
        echo ""
        echo "3. n8n Webhook 직접 호출:"
        echo "   curl -X POST http://localhost:5678/webhook/equipment-complete \\"
        echo "     -H \"Content-Type: application/json\" \\"
        echo "     -d '{\"sessionId\": \"test\", \"message\": \"1번 서버 상태 확인해줘\"}'"
        echo ""
        echo "✨ 주요 수정사항:"
        echo "- SSH 인증에 sshpass 사용으로 실제 서버 연결 가능"
        echo "- Prisma 데이터베이스 연결 문제 해결"
        echo "- 워크플로우 실행 기록 정상 저장"
        echo "- 모든 하드코딩 제거, 동적 처리"
        ;;
    "PARTIAL_SUCCESS")
        echo "⚠️ 수정 부분적 완료. 기본 기능은 작동하지만 일부 문제가 있을 수 있습니다."
        echo ""
        echo "📋 확인해야 할 사항:"
        echo "- 로그 확인: docker logs automation-workflow-engine --tail 50"
        echo "- 서비스 상태: docker ps | grep automation"
        ;;
    "FAILURE")
        echo "🚨 수정 실패. 시스템에 심각한 문제가 있습니다."
        echo ""
        echo "🔧 복구 방법:"
        echo "1. 백업 복원:"
        echo "   docker exec -i automation-postgres psql -U postgres -d automation < $BACKUP_DIR/postgres-backup.sql"
        echo ""
        echo "2. n8n 워크플로우 복원:"
        echo "   curl -X PUT -H \"X-N8N-API-KEY: $N8N_API_KEY\" \\"
        echo "     -H \"Content-Type: application/json\" \\"
        echo "     -d @$BACKUP_DIR/workflow-backup.json \\"
        echo "     http://localhost:5678/api/v1/workflows/IjJX9tJR4IPL76oa"
        ;;
esac

echo ""
echo "📁 백업 위치: $BACKUP_DIR"
echo "📁 수정 스크립트: $PROJECT_DIR/scripts/fixes"

# 8. 정리 작업
echo ""
echo "🧹 정리 작업..."

# 임시 파일 정리
rm -f /tmp/fixed-workflow.json

echo "✅ 정리 완료"

echo ""
echo "=============================================="
echo "🏁 통합 자동화 시스템 v3.1 수정 완료"

# 종료 코드 설정
case $TEST_RESULT in
    "SUCCESS") exit 0 ;;
    "PARTIAL_SUCCESS") exit 1 ;;
    "FAILURE") exit 2 ;;
esac

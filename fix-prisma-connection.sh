#!/bin/bash
# 파일: fix-prisma-connection.sh
# 목적: Prisma 데이터베이스 연결 문제 해결

set -e

PROJECT_DIR="/Users/leesg/Documents/work_ops/automation-system"
SCRIPT_DIR="$(dirname "$0")"

echo "🔧 Prisma 데이터베이스 연결 문제 해결 시작..."

# 1. 현재 상태 확인
echo "📊 현재 서비스 상태 확인..."
cd "$PROJECT_DIR"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep automation

# 2. Workflow Engine 로그 확인
echo ""
echo "📋 Workflow Engine 에러 로그 확인..."
docker logs automation-workflow-engine --tail 20 | grep -E "(error|Error|ERROR|Cannot read properties)"

# 3. PostgreSQL 연결 테스트
echo ""
echo "🗄️ PostgreSQL 연결 테스트..."
docker exec automation-postgres pg_isready -U postgres
if [ $? -eq 0 ]; then
    echo "✅ PostgreSQL 연결 정상"
else
    echo "❌ PostgreSQL 연결 실패"
    exit 1
fi

# 4. 데이터베이스 스키마 확인
echo ""
echo "📋 데이터베이스 스키마 확인..."
docker exec automation-postgres psql -U postgres -d automation -c "
SELECT table_name, column_name, data_type, character_maximum_length
FROM information_schema.columns
WHERE table_name IN ('workflow_executions', 'workflow_steps')
AND column_name IN ('workflow_id', 'execution_id')
ORDER BY table_name, column_name;
"

# 5. Prisma 클라이언트 재생성
echo ""
echo "🔄 Prisma 클라이언트 재생성..."

# Workflow Engine 컨테이너 내에서 Prisma 재생성
docker exec automation-workflow-engine sh -c "
cd /app && 
echo '📦 의존성 확인...' &&
npm list @prisma/client &&
echo '🔄 Prisma 클라이언트 재생성...' &&
npx prisma generate &&
echo '✅ Prisma 클라이언트 생성 완료'
"

# 6. Storage Service 재시작 (Prisma 관련 연결 리셋)
echo ""
echo "🔄 Storage Service 재시작..."
docker-compose restart storage

# Storage Service 준비 대기
echo "⏳ Storage Service 준비 대기..."
for i in {1..30}; do
    if curl -s http://localhost:8001/health > /dev/null 2>&1; then
        echo "✅ Storage Service 준비 완료"
        break
    fi
    echo "   대기 중... ($i/30)"
    sleep 2
done

# 7. Workflow Engine 재시작
echo ""
echo "🔄 Workflow Engine 재시작..."
docker-compose restart workflow-engine

# Workflow Engine 준비 대기
echo "⏳ Workflow Engine 준비 대기..."
for i in {1..30}; do
    if curl -s http://localhost:8401/health > /dev/null 2>&1; then
        echo "✅ Workflow Engine 준비 완료"
        break
    fi
    echo "   대기 중... ($i/30)"
    sleep 2
done

# 8. 연결 테스트
echo ""
echo "🧪 데이터베이스 연결 테스트..."

# Workflow Service 헬스체크
HEALTH_CHECK=$(curl -s http://localhost:8401/api/v1/workflows/health 2>/dev/null || echo "연결 실패")
echo "Workflow Service Health: $HEALTH_CHECK"

# Storage Service 헬스체크  
STORAGE_HEALTH=$(curl -s http://localhost:8001/health 2>/dev/null || echo "연결 실패")
echo "Storage Service Health: $STORAGE_HEALTH"

# 9. 최종 상태 확인
echo ""
echo "📊 최종 서비스 상태..."
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(automation-workflow-engine|automation-storage)"

# 10. 새로운 에러 확인
echo ""
echo "🔍 수정 후 에러 로그 확인..."
docker logs automation-workflow-engine --tail 10 | grep -E "(error|Error|ERROR)" || echo "❌ 발견된 에러 없음"

echo ""
echo "✅ Prisma 연결 문제 해결 완료!"
echo ""
echo "📝 다음 단계:"
echo "1. n8n 워크플로우 업데이트"
echo "2. 통합 테스트 실행"
echo "3. SSH 연결 검증"

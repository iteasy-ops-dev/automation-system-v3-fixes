#!/bin/bash
# 파일: update-n8n-workflow.sh
# 목적: n8n 워크플로우를 SSH 인증 수정 버전으로 업데이트

set -e

PROJECT_DIR="/Users/leesg/Documents/work_ops/automation-system"
SCRIPT_DIR="$(dirname "$0")"

echo "🔄 n8n 워크플로우 SSH 인증 수정 업데이트 시작..."

# 1. n8n API 키 설정
N8N_API_KEY="n8n_api_0953a966a0548abd7c3c1a8769e6976036b2dc3430d0de254799876277c00066b4c85bda8723f94d"
N8N_BASE_URL="http://localhost:5678"
WORKFLOW_ID="IjJX9tJR4IPL76oa"

# 2. 현재 워크플로우 상태 확인
echo "📊 현재 워크플로우 상태 확인..."
CURRENT_STATUS=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "$N8N_BASE_URL/api/v1/workflows/$WORKFLOW_ID" | jq -r '.active // "unknown"')

echo "현재 워크플로우 상태: $CURRENT_STATUS"

# 3. 기존 워크플로우 비활성화
if [ "$CURRENT_STATUS" = "true" ]; then
    echo "🛑 기존 워크플로우 비활성화..."
    curl -s -X POST -H "X-N8N-API-KEY: $N8N_API_KEY" \
      -H "Content-Type: application/json" \
      "$N8N_BASE_URL/api/v1/workflows/$WORKFLOW_ID/deactivate" > /dev/null
    echo "✅ 워크플로우 비활성화 완료"
fi

# 4. 수정된 워크플로우 정의로 업데이트
echo "📝 워크플로우 정의 업데이트..."

# 워크플로우 JSON을 GitHub에서 다운로드
echo "📥 GitHub에서 수정된 워크플로우 다운로드..."
curl -s -L "https://raw.githubusercontent.com/iteasy-ops-dev/automation-system-v3-fixes/main/fix-n8n-ssh-workflow.json" \
  -o "/tmp/fixed-workflow.json"

if [ ! -f "/tmp/fixed-workflow.json" ]; then
    echo "❌ 워크플로우 파일 다운로드 실패"
    exit 1
fi

echo "✅ 워크플로우 파일 다운로드 완료"

# 5. 워크플로우 업데이트 실행
echo "🔄 워크플로우 업데이트 실행..."
UPDATE_RESPONSE=$(curl -s -X PUT -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H "Content-Type: application/json" \
  -d @/tmp/fixed-workflow.json \
  "$N8N_BASE_URL/api/v1/workflows/$WORKFLOW_ID")

# 업데이트 결과 확인
if echo "$UPDATE_RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    echo "✅ 워크플로우 업데이트 성공"
    echo "워크플로우 ID: $(echo "$UPDATE_RESPONSE" | jq -r '.id')"
    echo "워크플로우 이름: $(echo "$UPDATE_RESPONSE" | jq -r '.name')"
else
    echo "❌ 워크플로우 업데이트 실패"
    echo "응답: $UPDATE_RESPONSE"
    exit 1
fi

# 6. 워크플로우 활성화
echo "🟢 워크플로우 활성화..."
ACTIVATE_RESPONSE=$(curl -s -X POST -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H "Content-Type: application/json" \
  "$N8N_BASE_URL/api/v1/workflows/$WORKFLOW_ID/activate")

if echo "$ACTIVATE_RESPONSE" | jq -e '.active' > /dev/null 2>&1; then
    echo "✅ 워크플로우 활성화 성공"
else
    echo "❌ 워크플로우 활성화 실패"
    echo "응답: $ACTIVATE_RESPONSE"
fi

# 7. 업데이트 후 상태 확인
echo ""
echo "📊 업데이트 후 워크플로우 상태 확인..."
FINAL_STATUS=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "$N8N_BASE_URL/api/v1/workflows/$WORKFLOW_ID")

echo "최종 상태:"
echo "- ID: $(echo "$FINAL_STATUS" | jq -r '.id')"
echo "- 이름: $(echo "$FINAL_STATUS" | jq -r '.name')"
echo "- 활성화: $(echo "$FINAL_STATUS" | jq -r '.active')"
echo "- 노드 수: $(echo "$FINAL_STATUS" | jq -r '.nodes | length')"

# 8. Webhook URL 확인
echo ""
echo "🔗 Webhook URL 확인..."
WEBHOOK_NODE=$(echo "$FINAL_STATUS" | jq -r '.nodes[] | select(.type == "n8n-nodes-base.webhook")')
if [ "$WEBHOOK_NODE" != "null" ] && [ "$WEBHOOK_NODE" != "" ]; then
    WEBHOOK_PATH=$(echo "$WEBHOOK_NODE" | jq -r '.parameters.path')
    echo "Webhook URL: $N8N_BASE_URL/webhook/$WEBHOOK_PATH"
else
    echo "⚠️ Webhook 노드를 찾을 수 없습니다"
fi

# 9. 임시 파일 정리
rm -f /tmp/fixed-workflow.json

echo ""
echo "✅ n8n 워크플로우 SSH 인증 수정 완료!"
echo ""
echo "📝 주요 변경사항:"
echo "1. SSH Connection Setup 노드에서 sshpass 사용"
echo "2. Device Service 내부 API로 복호화된 비밀번호 조회"
echo "3. 동적 SSH 명령어 생성"
echo ""
echo "🧪 테스트 준비 완료!"

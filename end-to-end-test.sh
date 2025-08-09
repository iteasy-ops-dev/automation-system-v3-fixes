#!/bin/bash
# 파일: end-to-end-test.sh
# 목적: SSH 인증 수정 후 전체 시스템 통합 테스트

set -e

PROJECT_DIR="/Users/leesg/Documents/work_ops/automation-system"
SCRIPT_DIR="$(dirname "$0")"

echo "🧪 통합 자동화 시스템 엔드투엔드 테스트 시작..."

# 테스트 결과 추적
declare -A TEST_RESULTS
TOTAL_TESTS=0
PASSED_TESTS=0

# 테스트 결과 기록 함수
record_test() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    TEST_RESULTS["$test_name"]="$result"
    
    if [ "$result" = "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo "✅ $test_name: PASS - $details"
    else
        echo "❌ $test_name: FAIL - $details"
    fi
}

# 1. 기본 서비스 상태 테스트
echo "📊 기본 서비스 상태 테스트..."

# 1.1. 모든 컨테이너 실행 중 확인
RUNNING_CONTAINERS=$(docker ps --format "{{.Names}}" | grep automation | wc -l)
if [ "$RUNNING_CONTAINERS" -ge 10 ]; then
    record_test "Container Status" "PASS" "$RUNNING_CONTAINERS containers running"
else
    record_test "Container Status" "FAIL" "Only $RUNNING_CONTAINERS containers running"
fi

# 1.2. 핵심 서비스 API 응답 확인
API_TESTS=(
    "http://localhost:8101/api/v1/devices/health:Device Service"
    "http://localhost:8201/api/v1/mcp/health:MCP Service"
    "http://localhost:8301/api/v1/llm/health:LLM Service"
    "http://localhost:8401/api/v1/workflows/health:Workflow Service"
    "http://localhost:5678/api/v1/workflows:n8n API"
)

for api_test in "${API_TESTS[@]}"; do
    IFS=':' read -r url service_name <<< "$api_test"
    
    if curl -s "$url" > /dev/null 2>&1; then
        record_test "$service_name API" "PASS" "API responding"
    else
        record_test "$service_name API" "FAIL" "API not responding"
    fi
done

# 2. SSH 연결 직접 테스트
echo ""
echo "🔐 SSH 연결 직접 테스트..."

# 2.1. sshpass 없이 연결 (실패해야 정상)
if timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@10.10.30.12 "echo test" 2>/dev/null; then
    record_test "SSH without password" "FAIL" "Should fail but succeeded"
else
    record_test "SSH without password" "PASS" "Correctly failed without password"
fi

# 2.2. sshpass로 연결 (성공해야 정상)
if timeout 10 sshpass -p "Zhtjgh*#20" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@10.10.30.12 "echo test" > /dev/null 2>&1; then
    record_test "SSH with sshpass" "PASS" "Successfully connected with sshpass"
else
    record_test "SSH with sshpass" "FAIL" "Failed to connect even with sshpass"
fi

# 3. Device Service 테스트
echo ""
echo "🖥️ Device Service 테스트..."

# 3.1. 장비 목록 조회
DEVICE_LIST=$(curl -s http://localhost:8101/api/v1/devices 2>/dev/null || echo "null")
if echo "$DEVICE_LIST" | jq -e '.[]' > /dev/null 2>&1; then
    DEVICE_COUNT=$(echo "$DEVICE_LIST" | jq 'length')
    record_test "Device List" "PASS" "$DEVICE_COUNT devices found"
else
    record_test "Device List" "FAIL" "No devices or API error"
fi

# 3.2. 특정 장비 조회 (1번 서버)
DEVICE_1=$(curl -s http://localhost:8101/api/v1/devices/by-name/1 2>/dev/null || echo "null")
if echo "$DEVICE_1" | jq -e '.id' > /dev/null 2>&1; then
    DEVICE_1_ID=$(echo "$DEVICE_1" | jq -r '.id')
    record_test "Device Query" "PASS" "Device '1' found: $DEVICE_1_ID"
else
    record_test "Device Query" "FAIL" "Device '1' not found"
fi

# 3.3. 연결 정보 조회 (내부 API)
CONNECTION_INFO=$(curl -s http://localhost:8101/api/v1/internal/devices/by-name/1/connection 2>/dev/null || echo "null")
if echo "$CONNECTION_INFO" | jq -e '.password' > /dev/null 2>&1; then
    record_test "Connection Info" "PASS" "Connection info retrieved with decrypted password"
else
    record_test "Connection Info" "FAIL" "Failed to retrieve connection info"
fi

# 4. MCP Service 테스트
echo ""
echo "⚡ MCP Service 테스트..."

# 4.1. MCP 서버 목록
MCP_SERVERS=$(curl -s http://localhost:8201/api/v1/mcp/servers 2>/dev/null || echo "null")
if echo "$MCP_SERVERS" | jq -e '.[]' > /dev/null 2>&1; then
    ACTIVE_SERVERS=$(echo "$MCP_SERVERS" | jq '[.[] | select(.status == "active")] | length')
    record_test "MCP Servers" "PASS" "$ACTIVE_SERVERS active MCP servers"
else
    record_test "MCP Servers" "FAIL" "No MCP servers found"
fi

# 4.2. Desktop Commander 직접 테스트
MCP_TEST_RESULT=$(curl -s -X POST http://localhost:8201/api/v1/mcp/execute \
  -H "Content-Type: application/json" \
  -d '{
    "serverId": "cbda6dfa-78a7-41a3-9986-869239873a72",
    "tool": "start_process",
    "params": {
      "command": "sshpass -p \"Zhtjgh*#20\" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@10.10.30.12 \"free -h\"",
      "timeout_ms": 15000
    },
    "async": false
  }' 2>/dev/null || echo "null")

if echo "$MCP_TEST_RESULT" | jq -e '.success' > /dev/null 2>&1 && \
   echo "$MCP_TEST_RESULT" | jq -e '.result.output' | grep -q "total"; then
    record_test "MCP SSH Execution" "PASS" "SSH command executed successfully via MCP"
else
    record_test "MCP SSH Execution" "FAIL" "SSH command failed via MCP"
fi

# 5. LLM Service 테스트
echo ""
echo "🤖 LLM Service 테스트..."

# 5.1. 의도 분석 테스트
LLM_TEST_RESULT=$(curl -s -X POST http://localhost:8301/api/v1/llm/chat \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "user",
        "content": "1번 서버의 메모리 사용량을 확인해줘"
      }
    ],
    "model": "gpt-4",
    "temperature": 0.1
  }' 2>/dev/null || echo "null")

if echo "$LLM_TEST_RESULT" | jq -e '.choices[0].message.content' > /dev/null 2>&1; then
    record_test "LLM Analysis" "PASS" "LLM responded correctly"
else
    record_test "LLM Analysis" "FAIL" "LLM did not respond"
fi

# 6. n8n 워크플로우 테스트
echo ""
echo "🔄 n8n 워크플로우 테스트..."

# 6.1. 워크플로우 상태 확인
N8N_API_KEY="n8n_api_0953a966a0548abd7c3c1a8769e6976036b2dc3430d0de254799876277c00066b4c85bda8723f94d"
WORKFLOW_ID="IjJX9tJR4IPL76oa"

WORKFLOW_STATUS=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "http://localhost:5678/api/v1/workflows/$WORKFLOW_ID" 2>/dev/null || echo "null")

if echo "$WORKFLOW_STATUS" | jq -e '.active' > /dev/null 2>&1; then
    IS_ACTIVE=$(echo "$WORKFLOW_STATUS" | jq -r '.active')
    if [ "$IS_ACTIVE" = "true" ]; then
        record_test "Workflow Status" "PASS" "Workflow is active"
    else
        record_test "Workflow Status" "FAIL" "Workflow is inactive"
    fi
else
    record_test "Workflow Status" "FAIL" "Could not check workflow status"
fi

# 6.2. Webhook 직접 테스트
echo ""
echo "🎯 Webhook 엔드투엔드 테스트..."

WEBHOOK_RESULT=$(curl -s -X POST http://localhost:5678/webhook/equipment-complete \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "test-e2e-session",
    "message": "1번 서버의 메모리 사용량을 알려줘"
  }' 2>/dev/null || echo "null")

if echo "$WEBHOOK_RESULT" | jq -e '.success' > /dev/null 2>&1; then
    SUCCESS_STATUS=$(echo "$WEBHOOK_RESULT" | jq -r '.success')
    RESPONSE_TEXT=$(echo "$WEBHOOK_RESULT" | jq -r '.response // "No response"')
    
    if [ "$SUCCESS_STATUS" = "true" ]; then
        record_test "E2E Workflow" "PASS" "Workflow executed successfully"
        echo "📋 응답 내용: $RESPONSE_TEXT"
    else
        record_test "E2E Workflow" "FAIL" "Workflow execution failed"
    fi
else
    record_test "E2E Workflow" "FAIL" "Webhook did not respond properly"
fi

# 7. 최종 워크플로우 서비스 테스트
echo ""
echo "🎪 최종 워크플로우 서비스 테스트..."

FINAL_TEST_RESULT=$(curl -s -X POST http://localhost:8401/api/v1/workflows/chat \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "final-test-session",
    "message": "1번 서버의 메모리 사용량을 확인해줘"
  }' 2>/dev/null || echo "null")

if echo "$FINAL_TEST_RESULT" | jq -e '.response' > /dev/null 2>&1; then
    FINAL_RESPONSE=$(echo "$FINAL_TEST_RESULT" | jq -r '.response')
    record_test "Chat Interface" "PASS" "Chat interface working"
    echo "💬 최종 응답: $FINAL_RESPONSE"
else
    record_test "Chat Interface" "FAIL" "Chat interface not working"
fi

# 8. 테스트 결과 요약
echo ""
echo "📊 테스트 결과 요약"
echo "===================="
echo "총 테스트: $TOTAL_TESTS"
echo "성공: $PASSED_TESTS"
echo "실패: $((TOTAL_TESTS - PASSED_TESTS))"
echo "성공률: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"

echo ""
echo "📋 세부 결과:"
for test_name in "${!TEST_RESULTS[@]}"; do
    result="${TEST_RESULTS[$test_name]}"
    if [ "$result" = "PASS" ]; then
        echo "✅ $test_name"
    else
        echo "❌ $test_name"
    fi
done

# 9. 최종 판정
echo ""
if [ "$PASSED_TESTS" -eq "$TOTAL_TESTS" ]; then
    echo "🎉 모든 테스트 통과! 시스템이 완전히 작동합니다."
    exit 0
elif [ "$PASSED_TESTS" -ge $((TOTAL_TESTS * 80 / 100)) ]; then
    echo "⚠️ 대부분의 테스트 통과. 일부 기능에 문제가 있을 수 있습니다."
    exit 1
else
    echo "🚨 다수의 테스트 실패. 시스템에 심각한 문제가 있습니다."
    exit 2
fi

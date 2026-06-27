# 字节跳动 AI 智能体 API 接入文档

## API 信息

- **API Key**: `your-doubao-api-key`
- **API 端点**: `https://ark.cn-beijing.volces.com/api/v3/chat/completions`
- **Endpoint ID**: `ep-m-20260306102307-bnzbl`
- **使用模型**: `doubao-seed-2-0-pro-260215`

## 请求示例

### cURL

```bash
curl -X POST "https://ark.cn-beijing.volces.com/api/v3/chat/completions" \
  -H "Authorization: Bearer your-doubao-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ep-m-20260306102307-bnzbl",
    "messages": [{"role": "user", "content": "你好"}]
  }'
```

### Python

```python
import requests

API_KEY = "your-doubao-api-key"
API_URL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

data = {
    "model": "ep-m-20260306102307-bnzbl",
    "messages": [{"role": "user", "content": "你好"}],
    "temperature": 1,
    "top_p": 0.95
}

response = requests.post(API_URL, headers=headers, json=data, timeout=30)

if response.status_code == 200:
    result = response.json()
    print(f"回复: {result['choices'][0]['message']['content']}")
    print(f"Token用量: {result['usage']}")
else:
    print(f"错误: {response.text}")
```

## 关键参数

- **model**: 使用 Endpoint ID（推荐）或 Model ID
- **messages**: 消息列表，支持 system/user/assistant/tool 角色
- **temperature**: 采样温度（0-2，默认 1）
- **top_p**: 核采样概率（0-1，默认 0.95）
- **max_tokens**: 最大输出长度（默认 4096）
- **stream**: 是否流式返回（默认 false，当前 Endpoint 不支持）

## 响应格式

```json
{
  "choices": [{
    "message": {
      "content": "回复内容",
      "reasoning_content": "思维链内容"
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 50,
    "completion_tokens": 174,
    "total_tokens": 224
  }
}
```

## 注意事项

1. 使用 Endpoint ID 而非 Model ID 更稳定
2. 该模型支持深度思考模式，会返回 `reasoning_content`
3. Token 用量包含思维链部分
4. 控制台地址: https://console.volcengine.com/ark/region:ark+cn-beijing/endpoint

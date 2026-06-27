# Claude模型API接入文档

## API信息
- **URL地址**: https://api.claudecode-ai.top/
- **密钥**: sk-your-claude-api-key

## 可用模型
- claude-opus-4-6

## 连接方法（示例）

### 1. 获取模型列表
```bash
curl -X GET "https://api.claudecode-ai.top/v1/models" \
  -H "x-api-key: sk-your-claude-api-key" \
  -H "anthropic-version: 2023-06-01"
```

### 2. 发送消息（支持中文）
```bash
curl -X POST "https://api.claudecode-ai.top/v1/messages" \
  -H "x-api-key: sk-your-claude-api-key" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json; charset=utf-8" \
  -d '{
    "model": "claude-opus-4-6",
    "max_tokens": 1024,
    "messages": [
      {"role": "user", "content": "你好，请用中文回复我"}
    ]
  }'
```

### 3. 流式响应（实时显示思考过程）
```bash
curl -N -X POST "https://api.claudecode-ai.top/v1/messages" \
  -H "x-api-key: sk-your-claude-api-key" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json; charset=utf-8" \
  -d '{
    "model": "claude-opus-4-6",
    "max_tokens": 1024,
    "stream": true,
    "messages": [
      {"role": "user", "content": "解释一下快速排序算法"}
    ]
  }'
```

**Python流式处理示例：**
```python
import requests

response = requests.post(
    "https://api.claudecode-ai.top/v1/messages",
    headers={
        "x-api-key": "sk-your-claude-api-key",
        "anthropic-version": "2023-06-01",
        "content-type": "application/json; charset=utf-8"
    },
    json={
        "model": "claude-opus-4-6",
        "max_tokens": 1024,
        "stream": True,
        "messages": [{"role": "user", "content": "解释快速排序"}]
    },
    stream=True
)

for line in response.iter_lines():
    if line:
        line = line.decode('utf-8')
        if line.startswith('data: '):
            data = line[6:]
            if 'text_delta' in data:
                import json
                delta = json.loads(data)
                print(delta['delta']['text'], end='', flush=True)
```

### 4. 图片识别（上传图片）

**方法1: 使用base64编码本地图片**
```python
import requests
import base64

with open("image.jpg", 'rb') as f:
    image_data = base64.b64encode(f.read()).decode('utf-8')

response = requests.post(
    "https://api.claudecode-ai.top/v1/messages",
    headers={
        "x-api-key": "sk-your-claude-api-key",
        "anthropic-version": "2023-06-01",
        "content-type": "application/json; charset=utf-8"
    },
    json={
        "model": "claude-opus-4-6",
        "max_tokens": 1024,
        "messages": [{
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": image_data
                    }
                },
                {"type": "text", "text": "这张图片里有什么？"}
            ]
        }]
    }
)
```

**方法2: 使用图片URL**
```bash
curl -X POST "https://api.claudecode-ai.top/v1/messages" \
  -H "x-api-key: sk-your-claude-api-key" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json; charset=utf-8" \
  -d '{
    "model": "claude-opus-4-6",
    "max_tokens": 1024,
    "messages": [{
      "role": "user",
      "content": [
        {
          "type": "image",
          "source": {
            "type": "url",
            "url": "https://example.com/image.jpg"
          }
        },
        {"type": "text", "text": "描述这张图片"}
      ]
    }]
  }'
```

**支持的图片格式**: JPEG, PNG, GIF, WebP

### 5. 会话管理（多轮对话）

**单次会话（无历史记录）**
```bash
curl -X POST "https://api.claudecode-ai.top/v1/messages" \
  -H "x-api-key: sk-your-claude-api-key" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json; charset=utf-8" \
  -d '{
    "model": "claude-opus-4-6",
    "max_tokens": 1024,
    "messages": [
      {"role": "user", "content": "你好，我叫张三"}
    ]
  }'
```

**多轮对话（带历史记录）**
```bash
curl -X POST "https://api.claudecode-ai.top/v1/messages" \
  -H "x-api-key: sk-your-claude-api-key" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json; charset=utf-8" \
  -d '{
    "model": "claude-opus-4-6",
    "max_tokens": 1024,
    "messages": [
      {"role": "user", "content": "My name is Tom"},
      {"role": "assistant", "content": "Hello Tom! Nice to meet you."},
      {"role": "user", "content": "What is my name?"}
    ]
  }'
```

**关键说明：**
- API是无状态的，每次请求独立
- 对话历史由客户端管理，需在messages数组中传递
- 新会话：清空messages数组
- 继续会话：包含完整历史记录

## 关键要点
1. **协议**: HTTPS (RESTful API)
2. **认证**: 使用 `x-api-key` header
3. **API版本**: `anthropic-version: 2023-06-01`
4. **中文支持**: Content-Type 需指定 `application/json; charset=utf-8`
5. **流式响应**: 设置 `"stream": true` 启用SSE流式输出
6. **图片识别**: 支持base64编码或URL两种方式
7. **端点**:
   - 模型列表: `/v1/models`
   - 发送消息: `/v1/messages`

## 测试结果
✓ API连接正常
✓ 中文字符显示正常
✓ 流式响应工作正常
✓ claude-opus-4-6 模型响应正常

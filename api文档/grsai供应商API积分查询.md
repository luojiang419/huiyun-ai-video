# Grsai API积分查询

## API端点

```
POST https://grsai.dakka.com.cn/client/openapi/getAPIKeyCredits
```

## 请求格式

```json
{
  "apiKey": "sk-xxxxxx"
}
```

## 响应格式

```json
{
  "code": 0,
  "data": {
    "createTime": 1772759056,
    "credits": 6440,
    "expireTime": 0,
    "type": 1
  },
  "msg": "success"
}
```

## 字段说明

- `credits`: 剩余积分
- `createTime`: 创建时间（Unix时间戳）
- `expireTime`: 过期时间（0表示无过期限制）
- `type`: 类型

## 使用示例

### curl

```bash
curl -X POST https://grsai.dakka.com.cn/client/openapi/getAPIKeyCredits \
  -H "Content-Type: application/json" \
  -d '{"apiKey":"sk-your-api-key"}'
```

### Python

```python
import requests

def get_api_credits(api_key):
    url = "https://grsai.dakka.com.cn/client/openapi/getAPIKeyCredits"
    response = requests.post(url, json={"apiKey": api_key})
    result = response.json()
    if result["code"] == 0:
        return result["data"]["credits"]
    return None
```

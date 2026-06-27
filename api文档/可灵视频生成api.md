# 可灵视频生成API文档

## API认证信息
- Access Key: `ArNmfHQyF3m4KaEH9MrJbaK4mBhgKH4a`
- Secret Key: `QAhnJMBAnkan4HMyKYPFEQaCeKYnRBCy`
- 调用域名: `https://api-beijing.klingai.com`

## JWT认证方法

```python
import time
import jwt

def encode_jwt_token(ak, sk):
    headers = {"alg": "HS256", "typ": "JWT"}
    payload = {
        "iss": ak,
        "exp": int(time.time()) + 1800,  # 有效期30分钟
        "nbf": int(time.time()) - 5       # 提前5秒生效
    }
    return jwt.encode(payload, sk, headers=headers)

token = encode_jwt_token(access_key, secret_key)
# Authorization: Bearer {token}
```

---

## 1. 图生视频 (Image2Video)

**接口**: `POST /v1/videos/image2video`

### 核心参数
- `model_name`: kling-v1/v1-5/v1-6/v2-master/v2-1/v2-1-master/v2-5-turbo/v2-6
- `image`: 参考图像（URL或Base64）
- `image_tail`: 尾帧图像（可选）
- `prompt`: 提示词（≤2500字符）
- `duration`: 5或10秒
- `mode`: std（标准）/pro（高品质）
- `sound`: on/off（仅V2.6+支持）

### 高级功能
- **运动笔刷**: `dynamic_masks`（动态）/`static_mask`（静态）
- **摄像机控制**: `camera_control`（运镜类型：simple/down_back/forward_up等）

### 示例
```bash
curl -X POST 'https://api-beijing.klingai.com/v1/videos/image2video' \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "model_name": "kling-v2-6",
    "image": "https://example.com/image.png",
    "prompt": "镜头拉远，女生微笑",
    "duration": "5",
    "mode": "pro"
  }'
```

---

## 2. Omni-Video (O1) - 多模态视频生成

**接口**: `POST /v1/videos/omni-video`

### 核心参数
- `model_name`: kling-video-o1
- `prompt`: 提示词（≤2500字符，支持`<<<image_1>>>`/`<<<video_1>>>`引用）
- `image_list`: 参考图片列表（最多7张，有视频时最多4张）
- `element_list`: 主体库ID列表
- `video_list`: 参考视频列表（最多1段）
- `duration`: 3-10秒
- `aspect_ratio`: 16:9/9:16/1:1
- `mode`: std/pro

### 使用场景

#### 2.1 文生视频
```json
{
  "model_name": "kling-video-o1",
  "prompt": "视频中的人跳舞",
  "mode": "pro",
  "aspect_ratio": "16:9",
  "duration": "7"
}
```

#### 2.2 图片/主体参考
```json
{
  "prompt": "<<<image_1>>>在东京街头漫步，偶遇<<<element_1>>>",
  "image_list": [{"image_url": "xxx"}],
  "element_list": [{"element_id": 123456}],
  "mode": "pro",
  "aspect_ratio": "1:1",
  "duration": "7"
}
```

#### 2.3 首尾帧控制
```json
{
  "prompt": "视频中的人跳舞",
  "image_list": [
    {"image_url": "xxx", "type": "first_frame"},
    {"image_url": "xxx", "type": "end_frame"}
  ],
  "mode": "pro"
}
```

#### 2.4 视频编辑（指令变换）
```json
{
  "prompt": "给<<<video_1>>>中的女孩戴上<<<image_1>>>中的王冠",
  "image_list": [{"image_url": "xxx"}],
  "video_list": [{
    "video_url": "xxx",
    "refer_type": "base",
    "keep_original_sound": "yes"
  }],
  "mode": "pro"
}
```

#### 2.5 视频参考（风格/运镜）
```json
{
  "prompt": "参考<<<video_1>>>的运镜方式生成视频",
  "video_list": [{
    "video_url": "xxx",
    "refer_type": "feature",
    "keep_original_sound": "yes"
  }],
  "mode": "pro",
  "aspect_ratio": "16:9",
  "duration": "7"
}
```

#### 2.6 视频延长
```json
{
  "prompt": "基于<<<video_1>>>，生成下一个镜头",
  "video_list": [{
    "video_url": "xxx",
    "refer_type": "feature"
  }],
  "mode": "pro"
}
```

---

## 3. 多图参考生视频

**接口**: `POST /v1/videos/multi-image2video`

### 核心参数
- `model_name`: kling-v1-6
- `image_list`: 最多4张图片
- `prompt`: 提示词
- `duration`: 5或10秒
- `aspect_ratio`: 16:9/9:16/1:1
- `mode`: std/pro

### 示例
```json
{
  "model_name": "kling-v1-6",
  "image_list": [
    {"image": "url1"},
    {"image": "url2"}
  ],
  "prompt": "一只白色比熊穿着红色花棉袄",
  "mode": "pro",
  "duration": "5",
  "aspect_ratio": "16:9"
}
```

---

## 任务查询

### 查询单个任务
```bash
GET /v1/videos/{api_type}/{task_id}
# api_type: image2video / omni-video / multi-image2video
```

### 查询任务列表
```bash
GET /v1/videos/{api_type}?pageNum=1&pageSize=30
```

### 响应格式
```json
{
  "code": 0,
  "data": {
    "task_id": "xxx",
    "task_status": "succeed",  // submitted/processing/succeed/failed
    "task_result": {
      "videos": [{
        "url": "xxx",
        "duration": "5"
      }]
    }
  }
}
```

---

## Python完整示例

```python
import time
import jwt
import requests
from pathlib import Path

ACCESS_KEY = "ArNmfHQyF3m4KaEH9MrJbaK4mBhgKH4a"
SECRET_KEY = "QAhnJMBAnkan4HMyKYPFEQaCeKYnRBCy"
BASE_URL = "https://api-beijing.klingai.com"

def encode_jwt_token(ak, sk):
    headers = {"alg": "HS256", "typ": "JWT"}
    payload = {
        "iss": ak,
        "exp": int(time.time()) + 1800,
        "nbf": int(time.time()) - 5
    }
    return jwt.encode(payload, sk, headers=headers)

def create_video(token, prompt):
    response = requests.post(
        f"{BASE_URL}/v1/videos/omni-video",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json={
            "model_name": "kling-video-o1",
            "prompt": prompt,
            "mode": "pro",
            "aspect_ratio": "16:9",
            "duration": "10"
        }
    )
    return response.json()

def query_task(token, task_id):
    response = requests.get(
        f"{BASE_URL}/v1/videos/omni-video/{task_id}",
        headers={"Authorization": f"Bearer {token}"}
    )
    return response.json()

def download_video(url, path):
    with open(path, 'wb') as f:
        for chunk in requests.get(url, stream=True).iter_content(8192):
            f.write(chunk)

# 使用示例
token = encode_jwt_token(ACCESS_KEY, SECRET_KEY)
result = create_video(token, "你的提示词")
task_id = result["data"]["task_id"]

# 轮询任务状态
while True:
    task_result = query_task(token, task_id)
    status = task_result["data"]["task_status"]
    if status == "succeed":
        video_url = task_result["data"]["task_result"]["videos"][0]["url"]
        download_video(video_url, "output.mp4")
        break
    elif status == "failed":
        print("生成失败")
        break
    time.sleep(10)
```

---

## 注意事项

1. **图片要求**: JPG/JPEG/PNG，≤10MB，≥300px，宽高比1:2.5~2.5:1
2. **视频要求**: MP4/MOV，3-10秒，720-2160px，≤200MB
3. **Base64编码**: 不要添加`data:image/png;base64,`前缀
4. **生成内容**: 30天后自动清理，请及时转存
5. **账户余额**: 确保账户有足够余额或资源包

## 错误码
- 1101: 账户欠费
- 1102: 资源包已用完
- 1301: 触发内容安全策略
- 1302: 请求过快，超过速率限制

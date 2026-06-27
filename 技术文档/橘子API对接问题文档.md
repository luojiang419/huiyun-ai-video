# 橘子视频生成API对接文档

## 当前问题

我们尝试使用外部图片URL调用橘子视频生成API时，收到错误响应：`"btwaf is from-data error"`

## API信息

### 接口地址
```
POST http://juziaigc.com/open/api/video
```

### 认证方式
```
Authorization: Bearer Y11u4irlWg0odm8w6SRmFANs6Hr0C5nQ
```

### Content-Type
```
multipart/form-data
```

## 请求参数

### 方式1：使用外部URL（失败）

```http
POST http://juziaigc.com/open/api/video
Authorization: Bearer Y11u4irlWg0odm8w6SRmFANs6Hr0C5nQ
Content-Type: multipart/form-data

model: VEO 3.1 Fast 多参考版
prompt: 男人用力的抬起轮胎，然后露出失望的表情
aspect_ratio: 9:16
image_urls[0]: http://115.231.35.105:8080/images/2026/03/20/img-20260320130403841.png
image_urls[1]: http://115.231.35.105:8080/images/2026/03/20/img-20260320130403841.png
```

**响应：**
```json
"btwaf is from-data error"
```

**状态码：** 200
**Content-Type：** application/json;

### 方式2：使用base64（成功）

```http
POST http://juziaigc.com/open/api/video
Authorization: Bearer Y11u4irlWg0odm8w6SRmFANs6Hr0C5nQ
Content-Type: multipart/form-data

model: VEO 3.1 Fast 多参考版
prompt: 测试提示词
aspect_ratio: 9:16
image_urls[0]: data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==
image_urls[1]: data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==
```

**响应：**
```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "juzi_id": "1a8d2df3-4b3c-49e9-9ad3-942126fbb97f"
  }
}
```

## 问题详情

### 1. 外部URL不被接受
- 我们的图片存储在：http://115.231.35.105:8080
- 图片可以正常访问（已验证）
- 但是API返回：`"btwaf is from-data error"`
- 推测：防火墙（btwaf）拦截了外部URL

### 2. Base64有大小限制
- 小图片（70字节base64）：✅ 成功
- 大图片（1.7MB，约2.3MB base64）：❌ 被防火墙拦截（403错误）

### 3. API文档示例使用OSS URL
根据API文档，示例使用的是阿里云OSS URL：
```
https://juziai.oss-cn-shenzhen.aliyuncs.com/uploads/20260301/f06aed0cb2ff8e1a131dd9ca6a56c781.png
```

## 需要确认的问题

### 问题1：image_urls参数支持的格式
请确认 `image_urls[0]` 和 `image_urls[1]` 参数支持哪些格式：

- [ ] Base64格式：`data:image/png;base64,iVBORw0KG...`
- [ ] 阿里云OSS URL：`https://juziai.oss-cn-shenzhen.aliyuncs.com/...`
- [ ] 外部HTTP URL：`http://115.231.35.105:8080/images/...`
- [ ] 外部HTTPS URL：`https://example.com/image.png`

### 问题2：Base64大小限制
如果支持base64格式，请确认：
- 单个图片base64的最大大小限制是多少？
- 整个请求body的最大大小限制是多少？

### 问题3：外部URL白名单
如果支持外部URL，是否需要：
- 将我们的服务器IP加入白名单？
- 使用HTTPS而不是HTTP？
- 特定的域名格式？

### 问题4：错误信息
`"btwaf is from-data error"` 的具体含义是什么？
- 是form-data格式错误？
- 是URL格式不支持？
- 是防火墙策略限制？

## 我们的需求

我们希望能够：
1. 使用外部URL传递参考图片（避免base64过大）
2. 或者，获得更大的base64大小限制（至少支持2-3MB的图片）
3. 或者，提供图片上传接口，先上传到你们的服务器，再使用返回的URL

## 测试代码

### Dart测试代码（使用外部URL）
```dart
final uri = Uri.parse('http://juziaigc.com/open/api/video');
final request = http.MultipartRequest('POST', uri);
request.headers['Authorization'] = 'Bearer Y11u4irlWg0odm8w6SRmFANs6Hr0C5nQ';

request.fields['model'] = 'VEO 3.1 Fast 多参考版';
request.fields['prompt'] = '男人用力的抬起轮胎，然后露出失望的表情';
request.fields['aspect_ratio'] = '9:16';
request.fields['image_urls[0]'] = 'http://115.231.35.105:8080/images/2026/03/20/img-20260320130403841.png';
request.fields['image_urls[1]'] = 'http://115.231.35.105:8080/images/2026/03/20/img-20260320130403841.png';

final streamResponse = await request.send();
final responseBytes = await streamResponse.stream.toBytes();
final responseBody = utf8.decode(responseBytes);

print('响应: $responseBody');
// 输出: "btwaf is from-data error"
```

### cURL测试命令（使用外部URL）
```bash
curl -X POST "http://juziaigc.com/open/api/video" \
  -H "Authorization: Bearer Y11u4irlWg0odm8w6SRmFANs6Hr0C5nQ" \
  -F "model=VEO 3.1 Fast 多参考版" \
  -F "prompt=男人用力的抬起轮胎，然后露出失望的表情" \
  -F "aspect_ratio=9:16" \
  -F "image_urls[0]=http://115.231.35.105:8080/images/2026/03/20/img-20260320130403841.png" \
  -F "image_urls[1]=http://115.231.35.105:8080/images/2026/03/20/img-20260320130403841.png"
```

### 测试图片URL
```
http://115.231.35.105:8080/images/2026/03/20/img-20260320130403841.png
```
- 图片大小：70 bytes
- 格式：PNG
- 可访问性：✅ 公网可访问
- 测试：在浏览器中打开该URL可以正常显示图片

## 响应详情

### 失败响应（使用外部URL）
```
状态码: 200
Content-Type: application/json;
响应体: "btwaf is from-data error"
```

### 成功响应（使用小base64）
```
状态码: 200
Content-Type: application/json;
响应体:
{
  "code": 200,
  "msg": "success",
  "data": {
    "juzi_id": "1a8d2df3-4b3c-49e9-9ad3-942126fbb97f"
  }
}
```

## 联系信息

如有任何问题或需要更多测试信息，请联系我们。

---

**文档生成时间：** 2026-03-20
**API版本：** 橘子视频生成API
**测试环境：** 生产环境

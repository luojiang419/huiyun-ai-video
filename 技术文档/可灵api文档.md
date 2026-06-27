可用api信息：
Access Key: ArNmfHQyF3m4KaEH9MrJbaK4mBhgKH4a
Secret Key: QAhnJMBAnkan4HMyKYPFEQaCeKYnRBCy

图生视频
创建任务
POST
/v1/videos/image2video
cURL

复制

折叠
curl --location --request POST 'https://api-beijing.klingai.com/v1/videos/image2video' \
--header 'Authorization: Bearer <token>' \
--header 'Content-Type: application/json' \
--data-raw '{
    "model_name": "kling-v2-6",
    "image": "https://p2-kling.klingai.com/kcdn/cdn-kcdn112452/kling-qa-test/multi-2.png",
    "image_tail": "https://p2-kling.klingai.com/kcdn/cdn-kcdn112452/kling-qa-test/multi-1.png",
    "prompt": "镜头拉远，女生微笑",
    "negative_prompt": "",
    "duration": "5",
    "mode": "pro",
    "sound": "off",
    "callback_url": "",
    "external_task_id": ""
}'
200

复制

折叠
{
  "code": 0, // 错误码；具体定义见错误码
  "message": "string", // 错误信息
  "request_id": "string", // 请求ID，系统生成，用于跟踪请求、排查问题
  "data": {
    "task_id": "string", // 任务ID，系统生成
    "task_info": { // 任务创建时的参数信息
      "external_task_id": "string" // 客户自定义任务ID
    },
    "task_status": "string", // 任务状态，枚举值：submitted（已提交）、processing（处理中）、succeed（成功）、failed（失败）
    "created_at": 1722769557708, // 任务创建时间，Unix时间戳、单位ms
    "updated_at": 1722769557708 // 任务更新时间，Unix时间戳、单位ms
  }
}
请您注意，为了保持命名统一，原 model 字段变更为 model_name 字段，未来请您使用该字段来指定需要调用的模型版本。
同时，我们保持了行为上的向前兼容，如您继续使用原 model 字段，不会对接口调用有任何影响、不会有任何异常，等价于 model_name 为空时的默认行为（即调用V1模型）
请求头
Content-Type
string
必填
默认值 application/json
数据交换格式

Authorization
string
必填
鉴权信息，参考接口鉴权

请求体
model_name
string
可选
默认值 kling-v1
模型名称

枚举值：
kling-v1
kling-v1-5
kling-v1-6
kling-v2-master
kling-v2-1
kling-v2-1-master
kling-v2-5-turbo
kling-v2-6
image
string
必填
参考图像

支持传入图片 Base64 编码或图片 URL（确保可访问）
注意：请确保您传递的所有图像数据参数均采用Base64编码格式。若您使用 Base64 方式，请不要在 Base64 编码字符串前添加任何前缀（如 data:image/png;base64,），直接传递 Base64 编码后的字符串即可。
正确的 Base64 编码参数：
iVBORw0KGgoAAAANSUhEUgAAAAUA...
错误的 Base64 编码参数（包含 data: 前缀）：
data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA...
图片格式支持 .jpg / .jpeg / .png
图片文件大小不能超过 10MB，图片宽高尺寸不小于 300px，图片宽高比介于 1:2.5 ~ 2.5:1 之间
image 参数与 image_tail 参数至少二选一，二者不能同时为空
image + image_tail 参数、dynamic_masks/static_mask 参数、camera_control 参数三选一，不能同时使用
不同模型版本、视频模式支持范围不同，详见能力地图
image_tail
string
可选
参考图像 - 尾帧控制

支持传入图片 Base64 编码或图片 URL（确保可访问）
注意：若您使用 Base64 方式，请不要在 Base64 编码字符串前添加任何前缀（如 data:image/png;base64,），直接传递 Base64 编码后的字符串即可。
图片格式支持 .jpg / .jpeg / .png
图片文件大小不能超过 10MB，图片宽高尺寸不小于 300px
image 参数与 image_tail 参数至少二选一，二者不能同时为空
image + image_tail 参数、dynamic_masks/static_mask 参数、camera_control 参数三选一，不能同时使用
不同模型版本、视频模式支持范围不同，详见能力地图
prompt
string
可选
正向文本提示词

不能超过 2500 个字符
用 <<<voice_1>>> 来指定音色，序号同 voice_list 参数所引用音色的排列顺序
一次视频生成任务至多引用 2 个音色；指定音色时，sound 参数值必须为 on
语法结构越简单越好，如：男人<<<voice_1>>>说："你好"
当 voice_list 参数不为空且 prompt 参数中引用音色 ID 时，视频生成任务按"有指定音色"计量计费
不同模型版本、视频模式支持范围不同，详见能力地图
negative_prompt
string
可选
负向文本提示词

不能超过 2500 个字符
voice_list
array
可选
生成视频时所引用的音色的列表

一次视频生成任务至多引用 2 个音色
当 voice_list 参数不为空且 prompt 参数中引用音色 ID 时，视频生成任务按"有指定音色"计量计费
voice_id 参数值通过音色定制接口返回，也可使用系统预置音色，详见音色定制相关API；非对口型 API 的 voice_id
示例：

"voice_list":[
  {"voice_id":"voice_id_1"},
  {"voice_id":"voice_id_2"}
]
仅 V2.6 及后续版本模型支持当前参数
sound
string
可选
默认值 off
生成视频时是否同时生成声音

枚举值：
on
off
仅 V2.6 及后续版本模型支持当前参数
cfg_scale
float
可选
默认值 0.5
生成视频的自由度；值越大，模型自由度越小，与用户输入的提示词相关性越强

取值范围：[0, 1]
kling-v2.x 模型不支持当前参数
mode
string
可选
默认值 std
生成视频的模式

枚举值：
std
pro
std：标准模式（标准），基础模式，性价比高
pro：专家模式（高品质），高表现模式，生成视频质量更佳
不同模型版本、视频模式支持范围不同，详见能力地图
static_mask
string
可选
静态笔刷涂抹区域（用户通过运动笔刷涂抹的 mask 图片）

"运动笔刷"能力包含"动态笔刷 dynamic_masks"和"静态笔刷 static_mask"两种
支持传入图片 Base64 编码或图片 URL（确保可访问，格式要求同 image 字段）
图片格式支持 .jpg / .jpeg / .png
图片长宽比必须与输入图片相同（即 image 字段），否则任务失败（failed）
static_mask 和 dynamic_masks.mask 这两张图片的分辨率必须一致，否则任务失败（failed）
不同模型版本、视频模式支持范围不同，详见能力地图
dynamic_masks
array
可选
动态笔刷配置列表

可配置多组（最多 6 组），每组包含"涂抹区域 mask"与"运动轨迹 trajectories"序列
不同模型版本、视频模式支持范围不同，详见能力地图
▾
隐藏 子属性
mask
string
必填
动态笔刷涂抹区域（用户通过运动笔刷涂抹的 mask 图片）

支持传入图片 Base64 编码或图片 URL（确保可访问，格式要求同 image 字段）
图片格式支持 .jpg / .jpeg / .png
图片长宽比必须与输入图片相同（即 image 字段），否则任务失败（failed）
static_mask 和 dynamic_masks.mask 这两张图片的分辨率必须一致，否则任务失败（failed）
trajectories
array
必填
运动轨迹坐标序列

生成 5s 的视频，轨迹长度不超过 77，即坐标个数取值范围：[2, 77]
轨迹坐标系，以图片左下角为坐标原点
注1：坐标点个数越多轨迹刻画越准确，如只有 2 个轨迹点则为这两点连接的直线
注2：轨迹方向以传入顺序为指向，以最先传入的坐标为轨迹起点，依次链接后续坐标形成运动轨迹
▾
隐藏 子属性
x
int
必填
轨迹点横坐标（在像素二维坐标系下，以输入图片 image 左下为原点的像素坐标）

y
int
必填
轨迹点纵坐标（在像素二维坐标系下，以输入图片 image 左下为原点的像素坐标）

camera_control
object
可选
控制摄像机运动的协议（如未指定，模型将根据输入的文本/图片进行智能匹配）

不同模型版本、视频模式支持范围不同，详见能力地图
▾
隐藏 子属性
type
string
必填
预定义的运镜类型

枚举值：
simple
down_back
forward_up
right_turn_forward
left_turn_forward
simple：简单运镜，此类型下可在"config"中六选一进行运镜
down_back：镜头下压并后退 ➡️ 下移拉远，此类型下 config 参数无需填写
forward_up：镜头前进并上仰 ➡️ 推进上移，此类型下 config 参数无需填写
right_turn_forward：先右旋转后前进 ➡️ 右旋推进，此类型下 config 参数无需填写
left_turn_forward：先左旋并前进 ➡️ 左旋推进，此类型下 config 参数无需填写
config
object
可选
包含六个字段，用于指定摄像机在不同方向上的运动或变化

当运镜类型指定 simple 时必填，指定其他类型时不填
以下参数 6 选 1，即只能有一个参数不为 0，其余参数为 0
▾
隐藏 子属性
horizontal
float
可选
水平运镜，控制摄像机在水平方向上的移动量（沿 x 轴平移）

取值范围：[-10, 10]，负值表示向左平移，正值表示向右平移
vertical
float
可选
垂直运镜，控制摄像机在垂直方向上的移动量（沿 y 轴平移）

取值范围：[-10, 10]，负值表示向下平移，正值表示向上平移
pan
float
可选
水平摇镜，控制摄像机在水平面上的旋转量（绕 y 轴旋转）

取值范围：[-10, 10]，负值表示绕 y 轴向左旋转，正值表示绕 y 轴向右旋转
tilt
float
可选
垂直摇镜，控制摄像机在垂直面上的旋转量（沿 x 轴旋转）

取值范围：[-10, 10]，负值表示绕 x 轴向下旋转，正值表示绕 x 轴向上旋转
roll
float
可选
旋转运镜，控制摄像机的滚动量（绕 z 轴旋转）

取值范围：[-10, 10]，负值表示绕 z 轴逆时针旋转，正值表示绕 z 轴顺时针旋转
zoom
float
可选
变焦，控制摄像机的焦距变化，影响视野的远近

取值范围：[-10, 10]，负值表示焦距变长、视野范围变小，正值表示焦距变短、视野范围变大
duration
string
可选
默认值 5
生成视频时长，单位 s

枚举值：
5
10
watermark_info
object
可选
是否同时生成含水印的结果

通过enabled参数定义，具体格式如下：
 "watermark_info": { "enabled": boolean } 
true 为生成，false 为不生成
暂不支持自定义水印
callback_url
string
可选
本次任务结果回调通知地址，如果配置，服务端会在任务状态发生变更时主动通知

具体通知的消息 schema 见 Callback 协议
external_task_id
string
可选
自定义任务 ID

用户自定义任务 ID，传入不会覆盖系统生成的任务 ID，但支持通过该 ID 进行任务查询
请注意，单用户下需要保证唯一性
查询任务（单个）
GET
/v1/videos/image2video/{id}
cURL

复制

折叠
curl --request GET \
  --url https://api-beijing.klingai.com/v1/videos/image2video/{task_id} \
  --header 'Authorization: Bearer <token>'
200

复制

折叠
{
  "code": 0, // 错误码；具体定义见错误码
  "message": "string", // 错误信息
  "request_id": "string", // 请求ID，系统生成，用于跟踪请求、排查问题
  "data": {
    "task_id": "string", // 任务ID，系统生成
    "task_status": "string", // 任务状态，枚举值：submitted（已提交）、processing（处理中）、succeed（成功）、failed（失败）
    "task_status_msg": "string", // 任务状态信息，当任务失败时展示失败原因（如触发平台的内容风控等）
    "final_unit_deduction": "string", // 任务最终扣减积分数值
    "watermark_info": {
      "enabled": boolean
    },
    "task_info": { // 任务创建时的参数信息
      "external_task_id": "string" // 客户自定义任务ID
    },
    "task_result": {
      "videos": [
        {
          "id": "string", // 生成的视频ID；全局唯一
          "url": "string", // 生成视频的URL（请注意，为保障信息安全，生成的图片/视频会在30天后被清理，请及时转存）
          "watermark_url": "string", // 含水印视频下载URL，防盗链格式
          "duration": "string" // 视频总时长，单位s
        }
      ]
    },
    "created_at": 1722769557708, // 任务创建时间，Unix时间戳、单位ms
    "updated_at": 1722769557708 // 任务更新时间，Unix时间戳、单位ms
  }
}
请求头
Content-Type
string
必填
默认值 application/json
数据交换格式

Authorization
string
必填
鉴权信息，参考接口鉴权

路径参数
task_id
string
可选
图生视频的任务 ID

请求路径参数，直接将值填写在请求路径中
与 external_task_id 两种查询方式二选一
external_task_id
string
可选
图生视频的自定义任务 ID

创建任务时填写的 external_task_id
与 task_id 两种查询方式二选一
查询任务（列表）
GET
/v1/videos/image2video
cURL

复制

折叠
curl --request GET \
  --url 'https://api-beijing.klingai.com/v1/videos/image2video?pageNum=1&pageSize=30' \
  --header 'Authorization: Bearer <token>'
200

复制

折叠
{
  "code": 0, // 错误码；具体定义见错误码
  "message": "string", // 错误信息
  "request_id": "string", // 请求ID，系统生成，用于跟踪请求、排查问题
  "data": [
    {
      "task_id": "string", // 任务ID，系统生成
      "task_status": "string", // 任务状态，枚举值：submitted（已提交）、processing（处理中）、succeed（成功）、failed（失败）
      "task_status_msg": "string", // 任务状态信息，当任务失败时展示失败原因（如触发平台的内容风控等）
      "final_unit_deduction": "string", // 任务最终扣减积分数值
      "watermark_info": {
        "enabled": boolean
      },
      "task_info": { // 任务创建时的参数信息
        "external_task_id": "string" // 客户自定义任务ID
      },
      "task_result": {
        "videos": [
          {
            "id": "string", // 生成的视频ID；全局唯一
            "url": "string", // 生成视频的URL（请注意，为保障信息安全，生成的图片/视频会在30天后被清理，请及时转存）
            "watermark_url": "string", // 含水印视频下载URL，防盗链格式
            "duration": "string" // 视频总时长，单位s
          }
        ]
      },
      "created_at": 1722769557708, // 任务创建时间，Unix时间戳、单位ms
      "updated_at": 1722769557708 // 任务更新时间，Unix时间戳、单位ms
    }
  ]
}
请求头
Content-Type
string
必填
默认值 application/json
数据交换格式

Authorization
string
必填
鉴权信息，参考接口鉴权

查询参数
pageNum
int
可选
默认值 1
页码

取值范围：[1, 1000]
pageSize
int
可选
默认值 30
每页数据量

取值范围：[1, 500]


Omni-Video（O1）
创建任务
POST
/v1/videos/omni-video
cURL

复制

折叠
curl --request POST \
  --url https://api-beijing.klingai.com/v1/videos/omni-video \
  --header 'Authorization: Bearer <token>' \
  --header 'Content-Type: application/json' \
  --data '{
  "model_name": "kling-video-o1",
  "prompt": "让<<<image_1>>>中的人物向镜头挥手",
  "image_list": [
    {
      "image_url": "https://p2-kling.klingai.com/kcdn/cdn-kcdn112452/kling-qa-test/multi-1.png"
    }
  ],
  "duration": "5",
  "mode": "pro",
  "aspect_ratio": "16:9",
  "callback_url": "",
  "external_task_id": ""
}'
200

复制

折叠
{
  "code": 0, // 错误码；具体定义见错误码
  "message": "string", // 错误信息
  "request_id": "string", // 请求ID，系统生成，用于跟踪请求、排查问题
  "data": {
    "task_id": "string", // 任务ID，系统生成
    "task_info": { //任务创建时的参数信息
      "external_task_id": "string" //客户自定义任务ID
    },
    "task_status": "string", // 任务状态，枚举值：submitted（已提交）、processing（处理中）、succeed（成功）、failed（失败）
    "created_at": 1722769557708, // 任务创建时间，Unix时间戳、单位ms
    "updated_at": 1722769557708 //任务更新时间，Unix时间戳、单位ms
  }
}
Omni 模型可以通过 Prompt 结合元素、图片、视频等内容实现多种能力。

请求头
Content-Type
string
必填
默认值 application/json
数据交换格式

Authorization
string
必填
鉴权信息，参考接口鉴权

请求体
model_name
string
可选
默认值 kling-video-o1
模型名称

枚举值：
kling-video-o1
prompt
string
必填
文本提示词，可包含正向描述和负向描述。

可将提示词模板化来满足不同的视频生成需求
不能超过 2,500 个字符
Omni模型可通过Prompt与主体、图片、视频等内容实现多种能力：

通过<<<>>>的格式来指定某个主体、图片或视频，如：<<<element_1>>>、<<<image_1>>>、<<<video_1>>>
能力范围详见使用手册：可灵Omni模型使用指南
image_list
array
可选
参考图列表，包括主体、场景、风格等参考图片。

首尾帧用法：

可作为首帧或尾帧生成视频
通过 type 参数定义：first_frame 为首帧，end_frame 为尾帧
暂时不支持仅尾帧，即有尾帧图时必须有首帧图
首帧或首尾帧生视频时，不能使用视频编辑功能
图片要求：

支持传入图片Base64编码或图片URL（确保可访问）
格式：.jpg / .jpeg / .png
文件大小：≤10MB
尺寸：宽和高都不小于300px，宽高比1:2.5 ~ 2.5:1
数量限制：

有参考视频时，参考图片数量不得超过4
无参考视频时，参考图片数量不得超过7
数组中超过2张图片时，不支持设置尾帧
image_url 参数值不得为空
▾
隐藏 子属性
image_url
string
必填
图片 URL 或 Base64

type
string
可选
帧类型：first_frame 为首帧，end_frame 为尾帧

枚举值：
first_frame
end_frame
element_list
array
可选
主体参考列表，基于主体库中主体的ID配置。

数量限制（与image_list合计）：

有参考视频时，参考图片数量和参考主体数量之和不得超过4
无参考视频时，参考图片数量和参考主体数量之和不得超过7
用 key:value 承载，如下：
"element_list":[
  { "element_id": 829836802793406551 }
]
▾
隐藏 子属性
element_id
long
必填
主体库中的主体 ID

video_list
array
可选
参考视频，通过URL方式获取。

视频类型：

可作为特征参考视频，也可作为待编辑视频，默认为待编辑视频
通过 refer_type 参数区分参考视频类型：feature 为特征参考视频，base 为待编辑视频
参考视频为待编辑视频时，不能定义视频首尾帧
通过 keep_original_sound 参数选择是否保留视频原声：yes 保留，no 不保留（对 feature 类型也生效）
视频要求：

格式：仅支持 MP4/MOV
时长：3-10秒
分辨率：720px-2160px（宽高尺寸）
帧率：24-60fps（生成视频时会输出为24fps）
至多1段视频，大小≤200MB
video_url 参数值不得为空
▾
隐藏 子属性
video_url
string
必填
视频 URL

refer_type
string
可选
默认值 base
参考类型：feature（特征参考视频）或 base（待编辑视频）

枚举值：
feature
base
base - 指令变换（视频编辑）：
视频编辑，例如增加/删除/修改内容（主体/背景/局部/视频风格/物体颜色/天气等），切换景别/视角。

feature - 视频参考：
参考视频内容生成下一个镜头/上一个镜头，或者参考视频的风格/运镜方式进行视频生成。

keep_original_sound
string
可选
保留原声：yes 保留，no 不保留

枚举值：
yes
no
mode
string
可选
默认值 pro
生成视频的模式

枚举值：
std
pro
其中std：标准模式（标准），基础模式，性价比高
其中pro：专家模式（高品质），高表现模式，生成视频质量更佳
不同模型版本、视频模式支持范围不同，详见 能力地图

aspect_ratio
string
可选
生成视频的画面纵横比（宽:高）

枚举值：
16:9
9:16
1:1
未使用首帧参考或视频编辑功能时，当前参数必填。
支持情况：

场景	是否支持
文生视频	✓
图片/主体参考	✓
视频参考 (其他)	✓
视频参考 (生成上一个/下一个镜头)	✓
指令变换（视频编辑, base）	✗
图生视频（首尾帧）	✗
duration
string
可选
默认值 5
生成视频时长，单位s

枚举值：
3
4
5
6
7
8
9
10
支持情况：

场景	支持值
文生视频、图生视频（不含首尾帧）	3-10
有视频输入（video_list不为空）且 使用视频编辑功能（refer_type: base）时：不可指定时长，跟视频对齐	跟随输入视频时长（参数无效）
其他情况（无视频+图片/主体生视频，或视频类型为 feature）	3-10
使用视频编辑功能时，按输入视频时长四舍五入取整计量计费。

watermark_info
object
可选
是否同时生成含水印的结果

通过enabled参数定义，具体格式如下：
 "watermark_info": { "enabled": boolean } 
true 为生成，false 为不生成
暂不支持自定义水印
callback_url
string
可选
本次任务结果回调通知地址，如果配置，服务端会在任务状态发生变更时主动通知。

具体通知的消息 schema 见 Callback 协议
external_task_id
string
可选
自定义任务ID。

传入不会覆盖系统生成的任务ID，但支持通过该ID进行任务查询。
请注意，单用户下需要保证唯一性。
更多场景调用示例
以下为场景代码示例,更多效果与提示词详见：可灵Omni模型示例

图片/主体参考
参考图片/主体里的角色/道具/场景等多种元素，灵活生成视频
cURL

复制

折叠
curl --location 'https://api-beijing.klingai.com/v1/videos/omni-video' \
--header 'Authorization: Bearer <token>' \
--header 'Content-Type: application/json' \
--data '{
    "model_name": "kling-video-o1",
    "prompt": "<<<image_1>>>在东京的街头漫步，偶遇<<<element_1>>>和<<<element_2>>>，并跳到<<<element_2>>>的怀里。视频画面风格与<<<image_2>>>相同",
    "image_list": [
        {
        	"image_url": "xxxxx"
        },
        {
        	"image_url": "xxxxx"
        }
    ],
    "element_list": [
        {
        	"element_id": long
        },
        {
        	"element_id": long
        }
    ],
    "mode": "pro",
    "aspect_ratio": "1:1",
    "duration": "7"
}'
指令变换
视频编辑，例如视频增加内容/删除内容/修改内容（主体/背景/局部/视频风格/物体颜色/天气/…）/切换景别/切换视角
cURL

复制

折叠
curl --location 'https://api-beijing.klingai.com/v1/videos/omni-video' \
--header 'Authorization: Bearer <token>' \
--header 'Content-Type: application/json' \
--data '{
    "model_name": "kling-video-o1",
    "prompt": "给<<<video_1>>>中的穿蓝衣服的女孩，戴上<<<image_1>>>中的王冠",
    "image_list": [
      {
      	"image_url": "xxx"
      }
    ],
    "video_list": [
      {
        "video_url":"xxxxxxxx",
        "refer_type":"base",
        "keep_original_sound":"yes"
      }
    ],
    "mode": "pro"
}'
视频参考
参考视频内容生成下一个镜头/上一个镜头，或者参考视频的风格/运镜方式进行视频生成
cURL

复制

折叠
curl --location 'https://api-beijing.klingai.com/v1/videos/omni-video' \
--header 'Authorization: Bearer <token>' \
--header 'Content-Type: application/json' \
--data '{
    "model_name": "kling-video-o1",
    "prompt": "参考<<<video_1>>>的运镜方式，生成一段视频：<<<element_1>>>和<<<element_2>>>在东京街头漫步，偶遇<<<image_1>>>",
    "image_list": [
      {
      	"image_url": "xxx"
      }
    ],
    "element_list": [
      {
      	"element_id": long
      },
      {
      	"element_id": long
      }
    ],
    "video_list": [
      {
        "video_url":"xxxxxxxx",
        "refer_type":"feature",
        "keep_original_sound":"yes"
      }
    ],
    "mode": "pro",
    "aspect_ratio": "1:1",
    "duration": "7"
}'
cURL

复制

折叠
curl --location 'https://api-beijing.klingai.com/v1/videos/omni-video' \
--header 'Authorization: Bearer <token>' \
--header 'Content-Type: application/json' \
--data '{
    "model_name": "kling-video-o1",
    "prompt": "基于<<<video_1>>>，生成下一个镜头",
    "video_list": [
      {
        "video_url":"xxxxxxxx",
        "refer_type":"feature",
        "keep_original_sound":"yes"
      }
    ],
    "mode": "pro"
}'
首尾帧
图生视频首尾帧
cURL

复制

折叠
curl --location 'https://api-beijing.klingai.com/v1/videos/omni-video' \
--header 'Authorization: Bearer <token>' \
--header 'Content-Type: application/json' \
--data '{
    "model_name": "kling-video-o1",
    "prompt": "视频中的人跳舞",
    "image_list": [
      {
      	"image_url": "xxx",
        "type": "first_frame"
      },
      {
      	"image_url": "xxx",
        "type": "end_frame"
      }
    ],
    "mode": "pro"
}'
文生视频
cURL

复制

折叠
curl --location 'https://api-beijing.klingai.com/v1/videos/omni-video' \
--header 'Authorization: Bearer <token>' \
--header 'Content-Type: application/json' \
--data '{
    "model_name": "kling-video-o1",
    "prompt": "视频中的人跳舞",
    "mode": "pro",
    "aspect_ratio": "1:1",
    "duration": "7"
}'
FAQ
1、生成视频时长（duration）什么情况支持、什么情况不支持？

文生，图生（不含首尾帧）：可选3~10s
有视频输入（video_list不为空）且 使用视频编辑功能（类型=base）时：不可指定时长，跟视频对齐
其他情况（不传视频+传图片+主体进行生视频，或者 传视频+视频类型=feature时），可选3-10s
2、怎么进行视频延长？

可以通过"视频参考"来实现，传入一段视频，通过prompt驱动模型"生成下一个镜头"或者"生成上一个镜头"
cURL

复制

折叠
curl --location 'https://api-beijing.klingai.com/v1/videos/omni-video' \
--header 'Authorization: Bearer <token>' \
--header 'Content-Type: application/json' \
--data '{
    "model_name": "kling-video-o1",
    "prompt": "基于<<<video_1>>>，生成下一个镜头",
    "video_list": [
      {
        "video_url":"xxxxxxxx",
        "refer_type":"feature",
        "keep_original_sound":"yes"
      }
    ],
    "mode": "pro"
}'
3、生成视频宽高比（aspect_ratio）什么情况支持、什么情况不支持？

不支持：指令变换（视频编辑），图生视频（包括首尾帧）
支持：文生视频，图片/主体参考，视频参考-其他，视频参考-生成下一个/上一个镜头
查询任务（单个）
GET
/v1/videos/omni-video/{id}
cURL

复制

折叠
curl --request GET \
  --url https://api-beijing.klingai.com/v1/videos/omni-video/{task_id} \
  --header 'Authorization: Bearer <token>'
200

复制

折叠
{
  "code": 0, // 错误码；具体定义见错误码
  "message": "string", // 错误信息
  "request_id": "string", // 请求ID，系统生成，用于跟踪请求、排查问题
  "data": {
    "task_id": "string", // 任务ID，系统生成
    "task_status": "string", // 任务状态，枚举值：submitted（已提交）、processing（处理中）、succeed（成功）、failed（失败）
    "task_status_msg": "string", // 任务状态信息，当任务失败时展示失败原因（如触发平台的内容风控等）
    "final_unit_deduction": "string", // 任务最终扣减积分数值
    "watermark_info": {
      "enabled": boolean
    },
    "task_info": { //任务创建时的参数信息
      "external_task_id": "string" //客户自定义任务ID
    },
    "task_result": {
      "videos": [
        {
          "id": "string", // 生成的视频ID；全局唯一
          "url": "string", // 生成视频的URL，防盗链格式（请注意，为保障信息安全，生成的图片/视频会在30天后被清理，请及时转存）
          "watermark_url": "string", // 含水印视频下载URL，防盗链格式
          "duration": "string" //视频总时长，单位s
        }
      ]
    },
    "created_at": 1722769557708, // 任务创建时间，Unix时间戳、单位ms
    "updated_at": 1722769557708 //任务更新时间，Unix时间戳、单位ms
  }
}
通过 ID 查询单个任务的状态和结果。

请求头
Content-Type
string
必填
默认值 application/json
数据交换格式

Authorization
string
必填
鉴权信息，参考接口鉴权

路径参数
task_id
string
可选
视频生成的任务ID。

请求路径参数，直接将值填写在请求路径中，与external_task_id两种查询方式二选一。

external_task_id
string
可选
视频生成的自定义任务ID。

创建任务时填写的external_task_id，与task_id两种查询方式二选一。

查询任务（列表）
GET
/v1/videos/omni-video
cURL

复制

折叠
curl --request GET \
  --url 'https://api-beijing.klingai.com/v1/videos/omni-video?pageNum=1&pageSize=30' \
  --header 'Authorization: Bearer <token>'
200

复制

折叠
{
  "code": 0, // 错误码；具体定义见错误码
  "message": "string", // 错误信息
  "request_id": "string", // 请求ID，系统生成，用于跟踪请求、排查问题
  "data": [
    {
      "task_id": "string", // 任务ID，系统生成
      "task_status": "string", // 任务状态，枚举值：submitted（已提交）、processing（处理中）、succeed（成功）、failed（失败）
      "task_status_msg": "string", // 任务状态信息，当任务失败时展示失败原因（如触发平台的内容风控等）
      "final_unit_deduction": "string", // 任务最终扣减积分数值
      "watermark_info": {
        "enabled": boolean
      },
      "task_info": { //任务创建时的参数信息
        "external_task_id": "string" //任务ID，客户自定义生成，与task_id两种查询方式二选一
      },
      "task_result": {
        "videos": [
          {
            "id": "string", // 生成的视频ID；全局唯一
            "url": "string", // 生成视频的URL，防盗链格式（请注意，为保障信息安全，生成的图片/视频会在30天后被清理，请及时转存）
            "watermark_url": "string", // 含水印视频下载URL，防盗链格式
            "duration": "string" //视频总时长，单位s
          }
        ]
      },
      "created_at": 1722769557708, // 任务创建时间，Unix时间戳、单位ms
      "updated_at": 1722769557708 //任务更新时间，Unix时间戳、单位ms
    }
  ]
}
分页查询任务列表。

请求头
Content-Type
string
必填
默认值 application/json
数据交换格式

Authorization
string
必填
鉴权信息，参考接口鉴权

查询参数
pageNum
int
可选
默认值 1
页码

取值范围：[1, 1000]

pageSize
int
可选
默认值 30
每页数据量

取值范围：[1, 500]


多图参考生视频
创建任务
POST
/v1/videos/multi-image2video
cURL

复制

折叠
curl --request POST \
  --url https://api-beijing.klingai.com/v1/videos/multi-image2video \
  --header 'Authorization: Bearer <token>' \
  --header 'Content-Type: application/json' \
  --data '{
    "model_name": "kling-v1-6",
    "image_list": [
      { "image": "https://p1-kling.klingai.com/kcdn/cdn-kcdn112452/kling-qa-test/dog.png" },
      { "image": "https://p1-kling.klingai.com/kcdn/cdn-kcdn112452/kling-qa-test/dog_cloth.png" }
    ],
    "prompt": "一只白色比熊穿着东北红色花棉袄，舔自己的手",
    "negative_prompt": "",
    "mode": "pro",
    "duration": "5",
    "aspect_ratio": "16:9",
    "callback_url": "",
    "external_task_id": ""
  }'
200

复制

折叠
{
  "code": 0, // 错误码；具体定义见错误码
  "message": "string", // 错误信息
  "request_id": "string", // 请求ID，系统生成，用于跟踪请求、排查问题
  "data": {
    "task_id": "string", // 任务ID，系统生成
    "task_status": "string", // 任务状态，枚举值：submitted（已提交）、processing（处理中）、succeed（成功）、failed（失败）
    "task_info": { //任务创建时的参数信息
      "external_task_id": "string" //客户自定义任务ID
    },
    "created_at": 1722769557708, // 任务创建时间，Unix时间戳、单位ms
    "updated_at": 1722769557708 //任务更新时间，Unix时间戳、单位ms
  }
}
基于多张参考图片（元素）生成视频。

请求头
Content-Type
string
必填
默认值 application/json
数据交换格式

Authorization
string
必填
鉴权信息，参考接口鉴权

请求体
model_name
string
可选
默认值 kling-v1-6
模型名称

枚举值：
kling-v1-6
image_list
array
必填
参考图片列表

最多支持 4 张图片，用 key:value 承载，如下：
"image_list":[
  { "image":"image_url" },
  { "image":"image_url" },
  { "image":"image_url" },
  { "image":"image_url" }
]
API 端无裁剪逻辑，请直接上传已选主体后的图片
支持传入图片 Base64 编码或图片 URL（确保可访问）
注意：若您使用 Base64 方式，请不要在 Base64 编码字符串前添加任何前缀（如 data:image/png;base64,），直接传递 Base64 编码后的字符串即可。
正确的 Base64 编码参数：
iVBORw0KGgoAAAANSUhEUgAAAAUA...
错误的 Base64 编码参数（包含 data: 前缀）：
data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA...
图片格式支持 .jpg / .jpeg / .png
图片文件大小不能超过 10MB，图片宽高尺寸不小于 300px，图片宽高比介于 1:2.5 ~ 2.5:1 之间
▾
隐藏 子属性
image
string
必填
图片 URL 或 Base64 字符串

prompt
string
必填
正向文本提示词

不能超过 2500 个字符
negative_prompt
string
可选
负向文本提示词

不能超过 2500 个字符
mode
string
可选
默认值 std
生成视频的模式

枚举值：
std
pro
其中std：标准模式（标准），基础模式，性价比高
其中pro：专家模式（高品质），高表现模式，生成视频质量更佳
不同模型版本、视频模式支持范围不同，详见 能力地图
duration
string
可选
默认值 5
生成视频时长，单位 s

枚举值：
5
10
aspect_ratio
string
可选
默认值 16:9
生成图片的画面纵横比（宽:高）

枚举值：
16:9
9:16
1:1
watermark_info
object
可选
是否同时生成含水印的结果

通过enabled参数定义，具体格式如下：
 "watermark_info": { "enabled": boolean } 
true 为生成，false 为不生成
暂不支持自定义水印
callback_url
string
可选
本次任务结果回调通知地址，如果配置，服务端会在任务状态发生变更时主动通知

具体通知的消息 schema 见 Callback 协议
external_task_id
string
可选
自定义任务 ID

用户自定义任务 ID，传入不会覆盖系统生成的任务 ID，但支持通过该 ID 进行任务查询
请注意，单用户下需要保证唯一性
查询任务（单个）
GET
/v1/videos/multi-image2video/{id}
cURL

复制

折叠
curl --request GET \
  --url https://api-beijing.klingai.com/v1/videos/multi-image2video/{task_id} \
  --header 'Authorization: Bearer <token>'
200

复制

折叠
{
  "code": 0, // 错误码；具体定义见错误码
  "message": "string", // 错误信息
  "request_id": "string", // 请求ID，系统生成，用于跟踪请求、排查问题
  "data": {
    "task_id": "string", // 任务ID，系统生成
    "task_status": "string", // 任务状态，枚举值：submitted（已提交）、processing（处理中）、succeed（成功）、failed（失败）
    "task_status_msg": "string", // 任务状态信息，当任务失败时展示失败原因（如触发平台的内容风控等）
    "final_unit_deduction": "string", // 任务最终扣减积分数值
    "watermark_info": {
      "enabled": boolean
    },
    "task_info": { //任务创建时的参数信息
      "external_task_id": "string" //客户自定义任务ID
    },
    "task_result": {
      "videos": [
        {
          "id": "string", // 生成的视频ID；全局唯一
          "url": "string", // 生成视频的URL（请注意，为保障信息安全，生成的图片/视频会在30天后被清理，请及时转存）
          "watermark_url": "string", // 含水印视频下载URL，防盗链格式
          "duration": "string" //视频总时长，单位s
        }
      ]
    },
    "created_at": 1722769557708, // 任务创建时间，Unix时间戳、单位ms
    "updated_at": 1722769557708 //任务更新时间，Unix时间戳、单位ms
  }
}
请求头
Content-Type
string
必填
默认值 application/json
数据交换格式

Authorization
string
必填
鉴权信息，参考接口鉴权

路径参数
task_id
string
可选
多图参考生视频的任务 ID

请求路径参数，直接将值填写在请求路径中
与 external_task_id 两种查询方式二选一
external_task_id
string
可选
多图参考生视频的自定义任务 ID

请求路径参数，直接将值填写在请求路径中
创建任务时填写的 external_task_id，与 task_id 两种查询方式二选一
查询任务（列表）
GET
/v1/videos/multi-image2video
cURL

复制

折叠
curl --request GET \
  --url 'https://api-beijing.klingai.com/v1/videos/multi-image2video?pageNum=1&pageSize=30' \
  --header 'Authorization: Bearer <token>'
200

复制

折叠
{
  "code": 0, // 错误码；具体定义见错误码
  "message": "string", // 错误信息
  "request_id": "string", // 请求ID，系统生成，用于跟踪请求、排查问题
  "data": [
    {
      "task_id": "string", // 任务ID，系统生成
      "task_status": "string", // 任务状态，枚举值：submitted（已提交）、processing（处理中）、succeed（成功）、failed（失败）
      "task_status_msg": "string", // 任务状态信息，当任务失败时展示失败原因（如触发平台的内容风控等）
      "final_unit_deduction": "string", // 任务最终扣减积分数值
      "watermark_info": {
        "enabled": boolean
      },
      "task_info": { //任务创建时的参数信息
        "external_task_id": "string" //客户自定义任务ID
      },
      "task_result": {
        "videos": [
          {
            "id": "string", // 生成的视频ID；全局唯一
            "url": "string", // 生成视频的URL（请注意，为保障信息安全，生成的图片/视频会在30天后被清理，请及时转存）
            "watermark_url": "string", // 含水印视频下载URL，防盗链格式
            "duration": "string" //视频总时长，单位s
          }
        ]
      },
      "created_at": 1722769557708, // 任务创建时间，Unix时间戳、单位ms
      "updated_at": 1722769557708 //任务更新时间，Unix时间戳、单位ms
    }
  ]
}
请求头
Content-Type
string
必填
默认值 application/json
数据交换格式

Authorization
string
必填
鉴权信息，参考接口鉴权

查询参数
pageNum
int
可选
默认值 1
页码

取值范围：[1, 1000]
pageSize
int
可选
默认值 30
每页数据量

取值范围：[1, 500]


文生音效
创建任务
POST
/v1/audio/text-to-audio
cURL

复制

折叠
curl --request POST \
  --url https://api-beijing.klingai.com/v1/audio/text-to-audio \
  --header 'Authorization: Bearer <token>' \
  --header 'Content-Type: application/json' \
  --data '{
    "prompt": "春节庆祝时的烟花声",
    "duration": 3,
    "external_task_id": "",
    "callback_url": ""
  }'
200

复制

折叠
{
  "code": 0, // 错误码；具体定义见错误码
  "message": "string", // 错误信息
  "request_id": "string", // 请求ID，系统生成，用于跟踪请求、排查问题
  "data": {
    "task_id": "string", // 任务ID，系统生成
    "task_info": { // 任务创建时的参数信息
      "external_task_id": "string" // 客户自定义任务ID
    },
    "task_status": "string", // 任务状态，枚举值：submitted（已提交）、processing（处理中）、succeed（成功）、failed（失败）
    "created_at": 1722769557708, // 任务创建时间，Unix时间戳、单位ms
    "updated_at": 1722769557708 // 任务更新时间，Unix时间戳、单位ms
  }
}
请求头
Content-Type
string
必填
默认值 application/json
数据交换格式

Authorization
string
必填
鉴权信息，参考接口鉴权

请求体
prompt
string
必填
文本提示词

内容长度不超过 200 字符
duration
float
必填
生成音频的时长

取值范围：3.0 秒至 10.0 秒，支持小数点后一位精度
external_task_id
string
可选
自定义任务 ID

用户自定义任务 ID，传入不会覆盖系统生成的任务 ID，但支持通过该 ID 进行任务查询
请注意，单用户下需要保证唯一性
callback_url
string
可选
本次任务结果回调通知地址，如果配置，服务端会在任务状态发生变更时主动通知

具体通知的消息 schema 见 Callback 协议
查询任务（单个）
GET
/v1/audio/text-to-audio/{id}
cURL

复制

折叠
curl --request GET \
  --url https://api-beijing.klingai.com/v1/audio/text-to-audio/{task_id} \
  --header 'Authorization: Bearer <token>' \
  --header 'Content-Type: application/json'
200

复制

折叠
{
  "code": 0, // 错误码；具体定义见错误码
  "message": "string", // 错误信息
  "request_id": "string", // 请求ID，系统生成，用于跟踪请求、排查问题
  "data": {
    "task_id": "string", // 任务ID，系统生成
    "task_status": "string", // 任务状态，枚举值：submitted（已提交）、processing（处理中）、succeed（成功）、failed（失败）
    "task_status_msg": "string", // 任务状态信息，当任务失败时展示失败原因（如触发平台的内容风控等）
    "final_unit_deduction": "string", // 任务最终扣减积分数值
    "task_info": { // 任务创建时的参数信息
      "external_task_id": "string" // 客户自定义任务ID
    },
    "task_result": {
      "audios": [
        {
          "id": "string", // 音频ID；全局唯一
          "url_mp3": "string", // 生成音频的URL，MP3格式（请注意，为保障信息安全，生成的音频会在30天后被清理，请及时转存）
          "url_wav": "string", // 生成音频的URL，WAV格式（请注意，为保障信息安全，生成的音频会在30天后被清理，请及时转存）
          "duration_mp3": "string", // MP3格式音频总时长，单位s
          "duration_wav": "string" // WAV格式音频总时长，单位s
        }
      ]
    },
    "created_at": 1722769557708, // 任务创建时间，Unix时间戳、单位ms
    "updated_at": 1722769557708 // 任务更新时间，Unix时间戳、单位ms
  }
}
请求头
Content-Type
string
必填
默认值 application/json
数据交换格式

Authorization
string
必填
鉴权信息，参考接口鉴权

路径参数
task_id
string
可选
文生音频的任务 ID

请求路径参数，直接将值填写在请求路径中
与 external_task_id 两种查询方式二选一
external_task_id
string
可选
用户自定义任务 ID

创建任务时填写的 external_task_id，与 task_id 两种查询方式二选一
查询任务（列表）
GET
/v1/audio/text-to-audio
cURL

复制

折叠
curl --request GET \
  --url 'https://api-beijing.klingai.com/v1/audio/text-to-audio?pageNum=1&pageSize=30' \
  --header 'Authorization: Bearer <token>' \
  --header 'Content-Type: application/json'
200

复制

折叠
{
  "code": 0, // 错误码；具体定义见错误码
  "message": "string", // 错误信息
  "request_id": "string", // 请求ID，系统生成，用于跟踪请求、排查问题
  "data": [
    {
      "task_id": "string", // 任务ID，系统生成
      "task_status": "string", // 任务状态，枚举值：submitted（已提交）、processing（处理中）、succeed（成功）、failed（失败）
      "task_status_msg": "string", // 任务状态信息，当任务失败时展示失败原因（如触发平台的内容风控等）
      "final_unit_deduction": "string", // 任务最终扣减积分数值
      "task_info": { // 任务创建时的参数信息
        "external_task_id": "string" // 客户自定义任务ID
      },
      "task_result": {
        "audios": [
          {
            "id": "string", // 音频ID；全局唯一
            "url_mp3": "string", // 生成音频的URL，MP3格式（请注意，为保障信息安全，生成的音频会在30天后被清理，请及时转存）
            "url_wav": "string", // 生成音频的URL，WAV格式（请注意，为保障信息安全，生成的音频会在30天后被清理，请及时转存）
            "duration_mp3": "string", // MP3格式音频总时长，单位s
            "duration_wav": "string" // WAV格式音频总时长，单位s
          }
        ]
      },
      "created_at": 1722769557708, // 任务创建时间，Unix时间戳、单位ms
      "updated_at": 1722769557708 // 任务更新时间，Unix时间戳、单位ms
    }
  ]
}
请求头
Content-Type
string
必填
默认值 application/json
数据交换格式

Authorization
string
必填
鉴权信息，参考接口鉴权

查询参数
pageNum
int
可选
默认值 1
页码

取值范围：[1, 1000]
pageSize
int
可选
默认值 30
每页数据量

取值范围：[1, 500]


通用信息
调用域名
https://api-beijing.klingai.com
接口鉴权
Step-1：获取 AccessKey + SecretKey
Step-2：您每次请求API的时候，需要按照固定加密方法生成API Token
加密方法：遵循JWT（Json Web Token, RFC 7519）标准
JWT由三个部分组成：Header、Payload、Signature
Python
Java

复制

折叠
import time
import jwt

ak = "" # 填写access key
sk = "" # 填写secret key

def encode_jwt_token(ak, sk):
    headers = {
        "alg": "HS256",
        "typ": "JWT"
    }
    payload = {
        "iss": ak,
        "exp": int(time.time()) + 1800, # 有效时间，此处示例代表当前时间+1800s(30min)
        "nbf": int(time.time()) - 5 # 开始生效的时间，此处示例代表当前时间-5秒
    }
    token = jwt.encode(payload, sk, headers=headers)
    return token

api_token = encode_jwt_token(ak, sk)
print(api_token) # 打印生成的API_TOKEN
Step-3：用第二步生成的API Token组装成Authorization，填写到 Request Header 里
组装方式：Authorization = “Bearer XXX”， 其中XXX填写第二步生成的API Token（注意Bearer跟XXX之间有空格）
错误码
HTTP状态码	业务码	业务码定义	业务码解释	建议解决方案
200	0	请求成功	-	-
401	1000	身份验证失败	身份验证失败	检查Authorization是否正确
401	1001	身份验证失败	Authorization为空	在RequestHeader中填写正确的Authorization
401	1002	身份验证失败	Authorization值非法	在RequestHeader中填写正确的Authorization
401	1003	身份验证失败	Authorization未到有效时间	检查token的开始生效时间，等待生效或重新签发
401	1004	身份验证失败	Authorization已失效	检查token的有效期，重新签发
429	1100	账户异常	账户异常	检查账户配置信息
429	1101	账户异常	账户欠费 (后付费场景)	进行账户充值，确保余额充足
429	1102	账户异常	资源包已用完/已过期（预付费场景）	购买额外的资源包，或开通后付费服务（如有）
403	1103	账户异常	请求的资源无权限，如接口/模型	检查账户权限
400	1200	请求参数非法	请求参数非法	检查请求参数是否正确
400	1201	请求参数非法	参数非法，如key写错或value非法	参考返回体中message字段的具体信息，修改请求参数
404	1202	请求参数非法	请求的method无效	查看接口文档，使用正确的requestmethod
404	1203	请求参数非法	请求的资源不存在，如模型	参考返回体中message字段的具体信息，修改请求参数
400	1300	触发策略	触发平台策略	检查是否触发平台策略
400	1301	触发策略	触发平台的内容安全策略	检查输入内容，修改后重新发起请求
429	1302	触发策略	API请求过快，超过平台速率限制	降低请求频率、稍后重试，或联系客服增加限额
429	1303	触发策略	并发或QPS超出预付费资源包限制	降低请求频率、稍后重试，或联系客服增加限额
429	1304	触发策略	触发平台的IP白名单策略	联系客服
500	5000	内部错误	服务器内部错误	稍后重试，或联系客服
503	5001	内部错误	服务器暂时不可用，通常是在维护	稍后重试，或联系客服
504	5002	内部错误	服务器内部超时，通常是发生积压	稍后重试，或联系客服
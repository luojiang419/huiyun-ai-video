
可用api密钥：sk-your-qwen-api-key

Python
import os
from openai import OpenAI
# 注意: 不同地域的base_url不通用（下方示例使用北京地域的 base_url）
# - 华北2（北京）: https://dashscope.aliyuncs.com/compatible-mode/v1
# - 新加坡: https://dashscope-intl.aliyuncs.com/compatible-mode/v1
client = OpenAI(
    api_key=os.getenv("DASHSCOPE_API_KEY"),
    base_url="https://dashscope.aliyuncs.com/compatible-mode/v1",
)
completion = client.chat.completions.create(
    model="qwen3.5-plus",
    messages=[{'role': 'user', 'content': '你是谁？'}]
)
print(completion.choices[0].message.content)


Node.js
import OpenAI from "openai";

// 注意: 不同地域的base_url不通用（下方示例使用北京地域的base_url）
// - 华北2（北京）: https://dashscope.aliyuncs.com/compatible-mode/v1
// - 新加坡: https://dashscope-intl.aliyuncs.com/compatible-mode/v1
const openai = new OpenAI(
    {
        apiKey: process.env.DASHSCOPE_API_KEY,
        baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
    }
);

async function main() {
    const completion = await openai.chat.completions.create({
        model: "qwen3.5-plus",
        messages: [{ role: "user", content: "你是谁？"}],
    });
    console.log(completion.choices[0].message.content)
}

main()


curl
curl -X POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions \
-H "Authorization: Bearer $DASHSCOPE_API_KEY" \
-H "Content-Type: application/json" \
-d '{
    "model": "qwen3.5-plus",
    "messages": [
        {
            "role": "user",
            "content": "你是谁？"
        }
    ]
}'

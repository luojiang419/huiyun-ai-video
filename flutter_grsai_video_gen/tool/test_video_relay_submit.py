import base64
import json
import sys
from pathlib import Path

import requests


RELAY_UPLOAD_URL = "http://115.231.35.105:3444/upload"
VIDEO_API_URL = "http://juziaigc.com/open/api/video"
VIDEO_API_KEY = "Y11u4irlWg0odm8w6SRmFANs6Hr0C5nQ"
LOCAL_PROXY = "http://127.0.0.1:7890"
TEST_PNG_BASE64 = (
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGP8z8Dwn4GBgYGJAQoAHxcC"
    "Ay9fF5QAAAAASUVORK5CYII="
)


def print_block(title, content):
    print(f"\n=== {title} ===")
    print(content)


def doh_lookup(session):
    result = {}
    for name, url in {
        "dns_google": "https://dns.google/resolve?name=juziaigc.com&type=A",
        "alidns": "https://223.5.5.5/resolve?name=juziaigc.com&type=A",
    }.items():
        try:
            response = session.get(url, timeout=20, verify=False)
            result[name] = {
                "status": response.status_code,
                "body": response.text[:1000],
            }
        except Exception as exc:
            result[name] = {"error": repr(exc)}
    return result


def upload_test_image(session, output_dir):
    image_path = output_dir / "relay-video-test.png"
    image_path.write_bytes(base64.b64decode(TEST_PNG_BASE64))
    payload = {
        "filename": image_path.name,
        "data": f"data:image/png;base64,{TEST_PNG_BASE64}",
    }
    response = session.post(RELAY_UPLOAD_URL, json=payload, timeout=30)
    response.raise_for_status()
    data = response.json()
    return {
        "path": str(image_path),
        "relay_url": data.get("url", ""),
        "raw": data,
    }


def build_cases(relay_url):
    common = {
        "model": "VEO 3.1 Fast 多参考版",
        "prompt": "测试提示词，红色方块轻微移动",
        "aspect_ratio": "16:9",
    }
    return {
        "relay_both": {
            **common,
            "image_urls[0]": relay_url,
            "image_urls[1]": relay_url,
        },
        "relay_with_webhook": {
            **common,
            "image_urls[0]": relay_url,
            "image_urls[1]": relay_url,
            "webhook_url": "http://127.0.0.1/callback",
        },
        "relay_host_header": {
            **common,
            "image_urls[0]": relay_url,
            "image_urls[1]": relay_url,
        },
    }


def submit_case(session, name, payload, *, direct_ip=None):
    url = VIDEO_API_URL if direct_ip is None else f"http://{direct_ip}/open/api/video"
    headers = {"Authorization": f"Bearer {VIDEO_API_KEY}"}
    if direct_ip is not None:
      headers["Host"] = "juziaigc.com"

    try:
        response = session.post(url, headers=headers, data=payload, timeout=30)
        return {
            "name": name,
            "url": url,
            "status": response.status_code,
            "headers": dict(response.headers),
            "body": response.text[:2000],
        }
    except Exception as exc:
        return {
            "name": name,
            "url": url,
            "error": repr(exc),
        }


def main():
    output_dir = Path(__file__).resolve().parent

    direct_session = requests.Session()
    proxy_session = requests.Session()
    proxy_session.proxies.update({
        "http": LOCAL_PROXY,
        "https": LOCAL_PROXY,
    })

    print_block("DoH 解析（直连）", json.dumps(doh_lookup(direct_session), ensure_ascii=False, indent=2))
    print_block("DoH 解析（代理）", json.dumps(doh_lookup(proxy_session), ensure_ascii=False, indent=2))

    relay_info = upload_test_image(direct_session, output_dir)
    print_block("中继上传结果", json.dumps(relay_info["raw"], ensure_ascii=False, indent=2))

    cases = build_cases(relay_info["relay_url"])
    results = []
    for name, payload in cases.items():
        results.append(submit_case(direct_session, f"{name}_direct", payload))
        results.append(submit_case(proxy_session, f"{name}_proxy", payload))
        if name == "relay_host_header":
            results.append(
                submit_case(
                    direct_session,
                    f"{name}_direct_ip",
                    payload,
                    direct_ip="198.18.0.77",
                )
            )

    print_block("视频 API 测试结果", json.dumps(results, ensure_ascii=False, indent=2))

    success = False
    for item in results:
        body = item.get("body", "")
        if "\"juzi_id\"" in body:
            success = True
            break

    if success:
        print_block("结论", "已拿到 juzi_id，说明中继图片 URL 提交成功。")
        return 0

    print_block("结论", "未拿到 juzi_id，请先检查视频 API 域名解析和上游服务可用性。")
    return 1


if __name__ == "__main__":
    sys.exit(main())

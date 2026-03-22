#!/usr/bin/env python3
# ============================================================
# cleanup_github.py
# GitHubのルート直下に残っている古いgzファイルを削除する。
# 新構造（地方/都道府県/市区町村）に移行済みのファイルが対象。
#
# 使い方:
#   python3 cleanup_github.py --check-only  # 削除対象の確認のみ
#   python3 cleanup_github.py               # 実際に削除
# ============================================================

import argparse
import http.client
import json
import os
import ssl
import sys
import time
import urllib.parse

GITHUB_OWNER  = "noanoa31500-byte"
GITHUB_REPO   = "maps"
GITHUB_BRANCH = "main"
GITHUB_API    = "https://api.github.com"

# index.json 以外のルート直下ファイルをすべて削除する
KEEP_FILES = {"index.json"}


def log(msg):
    print(f"[cleanup] {msg}", flush=True)


def get_token():
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        print("エラー: GITHUB_TOKEN が設定されていません")
        sys.exit(1)
    return token


def github_request(method, path, body=None):
    token = get_token()
    data  = json.dumps(body, ensure_ascii=True).encode("utf-8") if body else None
    parsed   = urllib.parse.urlparse(f"{GITHUB_API}{path}")
    selector = parsed.path
    if parsed.query:
        selector += "?" + parsed.query

    def h(s): return s.encode("ascii", "ignore").decode("ascii")
    headers = {
        "Authorization": h(f"token {token}"),
        "Accept":        "application/vnd.github+json",
        "Content-Type":  "application/json; charset=utf-8",
        "User-Agent":    "GapLess-pipeline",
    }
    if data:
        headers["Content-Length"] = str(len(data))

    ctx  = ssl.create_default_context()
    conn = http.client.HTTPSConnection(parsed.netloc, context=ctx, timeout=30)
    try:
        conn.request(method, selector, body=data, headers=headers)
        resp      = conn.getresponse()
        resp_body = resp.read().decode("utf-8")
        if resp.status == 404:
            return None
        if resp.status >= 400:
            log(f"  API {resp.status}: {resp_body[:100]}")
            return None
        return json.loads(resp_body) if resp_body else {}
    except Exception as e:
        log(f"  API失敗: {e}")
        return None
    finally:
        conn.close()


def get_root_files() -> list:
    """ルート直下のファイル一覧を取得する。"""
    result = github_request("GET",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/"
        f"?ref={GITHUB_BRANCH}")
    if not isinstance(result, list):
        return []
    return [f for f in result if f["type"] == "file"]


def delete_file(path, sha, message) -> bool:
    body = {
        "message": message.encode("ascii", "ignore").decode("ascii"),
        "sha":     sha,
        "branch":  GITHUB_BRANCH,
    }
    result = github_request("DELETE",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{path}", body)
    return result is not None


def main():
    parser = argparse.ArgumentParser(
        description="GitHubのルート直下にある index.json 以外のファイルをすべて削除する")
    parser.add_argument("--check-only", action="store_true",
                        help="削除対象を表示するだけ（削除しない）")
    args = parser.parse_args()

    log("ルートファイル一覧を取得中...")
    files = get_root_files()
    if not files:
        log("ファイルが見つかりませんでした")
        return

    # index.json 以外をすべて削除対象にする
    targets = [f for f in files if f["name"] not in KEEP_FILES]

    log(f"削除対象: {len(targets)} ファイル")
    for f in targets:
        log(f"  {f['name']} ({f.get('size', 0)//1024} KB)")

    if not targets:
        log("削除するファイルはありません")
        return

    if args.check_only:
        log("--check-only モード: 削除は実行しません")
        return

    # 削除実行
    deleted = 0
    failed  = 0
    for f in targets:
        log(f"削除中: {f['name']}")
        ok = delete_file(f["name"], f["sha"], f"Remove old file: {f['name']}")
        if ok:
            log(f"  完了: {f['name']}")
            deleted += 1
        else:
            log(f"  失敗: {f['name']}")
            failed += 1
        time.sleep(0.5)

    log(f"\n完了: {deleted} 削除 / {failed} 失敗")


if __name__ == "__main__":
    main()

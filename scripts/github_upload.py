#!/usr/bin/env python3
# ============================================================
# github_upload.py
# GitHub Contents API を使って gz ファイルを直接アップロードする。
# git clone / git push が不要。
#
# 使い方（他スクリプトからインポート）:
#   from github_upload import upload_file, upload_files
#
# 単体テスト:
#   python3 github_upload.py output/tokyo_hazard.gplh.gz
# ============================================================

import base64
import json
import os
import sys
import urllib.error
import urllib.request

# ─────────────────────────────────────────────
# 設定（環境変数 or ここに直接書く）
# ─────────────────────────────────────────────
# セキュリティのため、トークンはここに書かずに
# 環境変数 GITHUB_TOKEN に設定することを強く推奨します。
#
# Mac での設定方法:
#   export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
#   （~/.zprofile に書いておくと毎回設定不要）
#
# どうしても直書きしたい場合は HARDCODED_TOKEN に書く。
# ただしこのファイルをGitHubに上げると漏洩するので注意。

HARDCODED_TOKEN = ""   # 推奨しない。環境変数を使うこと。

GITHUB_OWNER = "noanoa31500-byte"
GITHUB_REPO  = "maps"
GITHUB_BRANCH = "main"
GITHUB_API    = "https://api.github.com"


def get_token() -> str:
    token = os.environ.get("GITHUB_TOKEN", "") or HARDCODED_TOKEN
    if not token:
        print("エラー: GitHub トークンが設定されていません。")
        print("以下を実行してから再度スクリプトを起動してください:")
        print("  export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx")
        sys.exit(1)
    return token


def api_request(method: str, path: str, body: dict = None) -> dict | None:
    """GitHub API にリクエストを送る。"""
    import http.client
    import ssl

    token = get_token()
    data  = json.dumps(body, ensure_ascii=True).encode("utf-8") if body else None

    parsed = urllib.parse.urlparse(f"{GITHUB_API}{path}")
    host   = parsed.netloc
    selector = parsed.path
    if parsed.query:
        selector += "?" + parsed.query

    ctx = ssl.create_default_context()
    conn = http.client.HTTPSConnection(host, context=ctx, timeout=30)
    headers = {
        "Authorization": f"token {token}",
        "Accept":        "application/vnd.github+json",
        "Content-Type":  "application/json; charset=utf-8",
        "User-Agent":    "GapLess-pipeline",
    }
    if data:
        headers["Content-Length"] = str(len(data))

    try:
        conn.request(method, selector, body=data, headers=headers)
        resp = conn.getresponse()
        resp_body = resp.read().decode("utf-8")
        if resp.status >= 400:
            print(f"  API エラー {resp.status}: {resp_body[:200]}")
            return None
        return json.loads(resp_body)
    except Exception as e:
        print(f"  リクエスト失敗: {e}")
        return None
    finally:
        conn.close()


def get_existing_sha(repo_path: str) -> str | None:
    """
    リポジトリ上に既にファイルが存在する場合その SHA を返す。
    更新（上書き）に必要。存在しない場合は None。
    """
    result = api_request(
        "GET",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{repo_path}"
        f"?ref={GITHUB_BRANCH}",
    )
    if result and "sha" in result:
        return result["sha"]
    return None


def upload_file(local_path: str, repo_path: str = None,
                commit_message: str = None) -> bool:
    """
    ローカルファイルを GitHub リポジトリに直接アップロードする。

    Args:
        local_path:      アップロードするローカルファイルのパス
        repo_path:       リポジトリ内のパス（省略時はファイル名のみ）
        commit_message:  コミットメッセージ（省略時は自動生成）
    """
    if not os.path.exists(local_path):
        print(f"  ファイルが見つかりません: {local_path}")
        return False

    if repo_path is None:
        repo_path = os.path.basename(local_path)

    if commit_message is None:
        commit_message = f"Add {os.path.basename(local_path)}"
    # HTTPヘッダーに使えるようASCII外の文字を除去
    commit_message = commit_message.encode("ascii", errors="ignore").decode("ascii")

    # ファイルを base64 エンコード
    with open(local_path, "rb") as f:
        content_b64 = base64.b64encode(f.read()).decode("utf-8")

    file_size_kb = os.path.getsize(local_path) // 1024
    print(f"  アップロード中: {repo_path} ({file_size_kb} KB)")

    # 既存ファイルの SHA を取得（更新の場合に必要）
    sha = get_existing_sha(repo_path)

    body = {
        "message": commit_message,
        "content": content_b64,
        "branch":  GITHUB_BRANCH,
    }
    if sha:
        body["sha"] = sha
        print(f"  既存ファイルを更新 (SHA: {sha[:8]}...)")
    else:
        print(f"  新規ファイルを作成")

    result = api_request(
        "PUT",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{repo_path}",
        body,
    )

    if result and "content" in result:
        print(f"  完了: https://github.com/{GITHUB_OWNER}/{GITHUB_REPO}/blob/{GITHUB_BRANCH}/{repo_path}")
        # アップロード成功後にローカルファイルを削除
        try:
            os.remove(local_path)
            print(f"  削除: {local_path}")
        except Exception as e:
            print(f"  削除失敗（無視）: {e}")
        return True
    else:
        print(f"  アップロード失敗: {repo_path}")
        return False


def upload_files(file_pairs: list[tuple[str, str]],
                 commit_prefix: str = "Add map data") -> tuple[int, int]:
    """
    複数ファイルをまとめてアップロードする。
    phrases ファイル（*_phrases.*）は自動的にスキップする。

    Args:
        file_pairs: [(local_path, repo_path), ...] のリスト
        commit_prefix: コミットメッセージのプレフィックス

    Returns:
        (成功数, 失敗数)
    """
    succeeded = 0
    failed    = 0
    for local_path, repo_path in file_pairs:
        # phrases ファイルはアップロード対象外
        if "_phrases." in os.path.basename(local_path):
            print(f"  スキップ（phrases）: {os.path.basename(local_path)}")
            continue
        msg = f"{commit_prefix}: {os.path.basename(local_path)}"
        ok = upload_file(local_path, repo_path, msg)
        if ok:
            succeeded += 1
        else:
            failed += 1
    return succeeded, failed


# ─────────────────────────────────────────────
# 単体テスト用
# ─────────────────────────────────────────────
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("使い方: python3 github_upload.py <ローカルファイルパス> [リポジトリ内パス]")
        print("例:     python3 github_upload.py output/tokyo_hazard.gplh.gz")
        sys.exit(1)

    local  = sys.argv[1]
    remote = sys.argv[2] if len(sys.argv) >= 3 else os.path.basename(local)
    ok = upload_file(local, remote)
    sys.exit(0 if ok else 1)

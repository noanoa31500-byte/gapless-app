#!/usr/bin/env python3
# ============================================================
# reorganize_github.py
# GitHubのリポジトリ構造を以下に再編する。
#
# 変更前:
#   miyagi/
#     miyagi_sendai_roads.gplb.gz
#     miyagi_sendai_poi.gplb.gz
#
# 変更後:
#   tohoku/
#     miyagi/
#       miyagi_sendai/
#         miyagi_sendai_roads.gplb.gz
#         miyagi_sendai_poi.gplb.gz
#
# 使い方:
#   python3 reorganize_github.py              # 全県を再編
#   python3 reorganize_github.py miyagi       # 宮城県だけ
#   python3 reorganize_github.py --check-only # 移動先の確認のみ
#   python3 reorganize_github.py --dry-run    # アップロードはしない
# ============================================================

import argparse
import base64
import http.client
import json
import os
import re
import ssl
import sys
import time
import urllib.parse
import urllib.request

GITHUB_OWNER  = "noanoa31500-byte"
GITHUB_REPO   = "maps"
GITHUB_BRANCH = "main"
GITHUB_API    = "https://api.github.com"

# ─────────────────────────────────────────────
# 地方区分
# ─────────────────────────────────────────────
REGIONS = {
    "hokkaido": "hokkaido",
    "aomori":   "tohoku",
    "iwate":    "tohoku",
    "miyagi":   "tohoku",
    "akita":    "tohoku",
    "yamagata": "tohoku",
    "fukushima":"tohoku",
    "ibaraki":  "kanto",
    "tochigi":  "kanto",
    "gunma":    "kanto",
    "saitama":  "kanto",
    "chiba":    "kanto",
    "tokyo":    "kanto",
    "kanagawa": "kanto",
    "niigata":  "chubu",
    "toyama":   "chubu",
    "ishikawa": "chubu",
    "fukui":    "chubu",
    "yamanashi":"chubu",
    "nagano":   "chubu",
    "shizuoka": "chubu",
    "aichi":    "chubu",
    "mie":      "chubu",
    "shiga":    "kinki",
    "kyoto":    "kinki",
    "osaka":    "kinki",
    "hyogo":    "kinki",
    "nara":     "kinki",
    "wakayama": "kinki",
    "tottori":  "chugoku",
    "shimane":  "chugoku",
    "okayama":  "chugoku",
    "hiroshima":"chugoku",
    "yamaguchi":"chugoku",
    "tokushima":"shikoku",
    "kagawa":   "shikoku",
    "ehime":    "shikoku",
    "kochi":    "shikoku",
    "fukuoka":  "kyushu",
    "saga":     "kyushu",
    "nagasaki": "kyushu",
    "kumamoto": "kyushu",
    "oita":     "kyushu",
    "miyazaki": "kyushu",
    "kagoshima":"kyushu",
    "okinawa":  "kyushu",
}

REGION_LABELS = {
    "hokkaido": "北海道",
    "tohoku":   "東北",
    "kanto":    "関東",
    "chubu":    "中部",
    "kinki":    "近畿",
    "chugoku":  "中国",
    "shikoku":  "四国",
    "kyushu":   "九州・沖縄",
}

PREFECTURES = {
    "hokkaido":"北海道","aomori":"青森県","iwate":"岩手県","miyagi":"宮城県",
    "akita":"秋田県","yamagata":"山形県","fukushima":"福島県","ibaraki":"茨城県",
    "tochigi":"栃木県","gunma":"群馬県","saitama":"埼玉県","chiba":"千葉県",
    "tokyo":"東京都","kanagawa":"神奈川県","niigata":"新潟県","toyama":"富山県",
    "ishikawa":"石川県","fukui":"福井県","yamanashi":"山梨県","nagano":"長野県",
    "shizuoka":"静岡県","aichi":"愛知県","mie":"三重県","shiga":"滋賀県",
    "kyoto":"京都府","osaka":"大阪府","hyogo":"兵庫県","nara":"奈良県",
    "wakayama":"和歌山県","tottori":"鳥取県","shimane":"島根県","okayama":"岡山県",
    "hiroshima":"広島県","yamaguchi":"山口県","tokushima":"徳島県","kagawa":"香川県",
    "ehime":"愛媛県","kochi":"高知県","fukuoka":"福岡県","saga":"佐賀県",
    "nagasaki":"長崎県","kumamoto":"熊本県","oita":"大分県","miyazaki":"宮崎県",
    "kagoshima":"鹿児島県","okinawa":"沖縄県",
}


def log(msg):
    print(f"[reorganize] {msg}", flush=True)


# ─────────────────────────────────────────────
# GitHub API
# ─────────────────────────────────────────────
def get_token():
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        print("エラー: GITHUB_TOKEN が設定されていません")
        print("export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx")
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
    conn = http.client.HTTPSConnection(parsed.netloc, context=ctx, timeout=60)
    try:
        conn.request(method, selector, body=data, headers=headers)
        resp      = conn.getresponse()
        resp_body = resp.read().decode("utf-8")
        if resp.status == 404:
            return None
        if resp.status >= 400:
            log(f"  API {resp.status}: {resp_body[:100]}")
            return None
        return json.loads(resp_body)
    except Exception as e:
        log(f"  API失敗: {e}")
        return None
    finally:
        conn.close()


def get_folder_files(path) -> list:
    """指定パスのファイル一覧を返す。フォルダでなければ空リスト。"""
    result = github_request("GET",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{path}"
        f"?ref={GITHUB_BRANCH}")
    if not isinstance(result, list):
        return []
    return result


def download_file(download_url) -> bytes | None:
    try:
        req = urllib.request.Request(
            download_url, headers={"User-Agent": "GapLess-pipeline"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.read()
    except Exception as e:
        log(f"  ダウンロード失敗: {e}")
        return None


def upload_file(repo_path, content_bytes, commit_message) -> bool:
    content_b64 = base64.b64encode(content_bytes).decode("utf-8")
    # 既存SHAを取得
    existing = github_request("GET",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{repo_path}"
        f"?ref={GITHUB_BRANCH}")
    sha = existing.get("sha") if existing else None
    body = {
        "message": commit_message.encode("ascii", "ignore").decode("ascii"),
        "content": content_b64,
        "branch":  GITHUB_BRANCH,
    }
    if sha:
        body["sha"] = sha
    result = github_request("PUT",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{repo_path}", body)
    return result is not None and "content" in result


def delete_file(repo_path, sha, commit_message) -> bool:
    body = {
        "message": commit_message.encode("ascii", "ignore").decode("ascii"),
        "sha":     sha,
        "branch":  GITHUB_BRANCH,
    }
    result = github_request("DELETE",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/contents/{repo_path}", body)
    return result is not None


# ─────────────────────────────────────────────
# ファイル名から市区町村名を抽出
# ─────────────────────────────────────────────
def extract_municipality(filename, pref_key) -> str:
    """
    ファイル名から市区町村フォルダ名を決定する。
    例: miyagi_sendai_roads.gplb.gz → miyagi_sendai
        miyagi_sendai_poi_hospital.gplb.gz → miyagi_sendai
    """
    base = filename
    # 拡張子を除去
    for ext in [".gplb.gz", ".gplh.gz", ".gplb", ".gplh", ".json"]:
        if base.endswith(ext):
            base = base[:-len(ext)]
            break

    # サフィックスを除去
    for suffix in ["_roads", "_poi_hospital", "_poi_shelter",
                   "_poi_store", "_poi_water", "_poi", "_hazard"]:
        if base.endswith(suffix):
            base = base[:-len(suffix)]
            break

    # pref_key_ で始まっていれば市区町村名
    if base.startswith(pref_key + "_"):
        return base

    # index.json などはルートに置く
    return None


# ─────────────────────────────────────────────
# 1県の再編処理
# ─────────────────────────────────────────────
def reorganize_prefecture(pref_key, check_only, dry_run):
    region     = REGIONS.get(pref_key, "other")
    pref_ja    = PREFECTURES.get(pref_key, pref_key)
    region_ja  = REGION_LABELS.get(region, region)

    log(f"\n{pref_ja}（{region_ja}/{pref_key}）")

    # 現在の県フォルダのファイル一覧を取得
    files = get_folder_files(pref_key)
    if not files:
        log(f"  {pref_key}/ フォルダが見つかりません。スキップ。")
        return 0, 0

    # ファイルを市区町村ごとにグループ化
    groups: dict[str, list] = {}
    for f in files:
        if f["type"] != "file":
            continue
        muni = extract_municipality(f["name"], pref_key)
        if muni is None:
            log(f"  スキップ（市区町村不明）: {f['name']}")
            continue
        if muni not in groups:
            groups[muni] = []
        groups[muni].append(f)

    log(f"  市区町村数: {len(groups)} / ファイル数: {len(files)}")

    if check_only:
        for muni, flist in sorted(groups.items()):
            new_path = f"{region}/{pref_key}/{muni}/"
            log(f"  {pref_key}/{muni}/ → {new_path} ({len(flist)}ファイル)")
        return len(groups), 0

    moved  = 0
    failed = 0

    for muni, flist in groups.items():
        new_folder = f"{region}/{pref_key}/{muni}"
        for f in flist:
            old_path = f"{pref_key}/{f['name']}"
            new_path = f"{new_folder}/{f['name']}"

            if dry_run:
                log(f"  [dry-run] {old_path} → {new_path}")
                moved += 1
                continue

            # ダウンロード
            content = download_file(f["download_url"])
            if content is None:
                failed += 1
                continue

            # 新パスにアップロード
            ok = upload_file(new_path, content,
                             f"Move to {region}/{pref_key}/{muni}")
            if not ok:
                log(f"  アップロード失敗: {new_path}")
                failed += 1
                continue

            # 旧パスを削除
            ok = delete_file(old_path, f["sha"],
                             f"Remove old: {old_path}")
            if ok:
                log(f"  移動完了: {old_path} → {new_path}")
                moved += 1
            else:
                log(f"  削除失敗（旧ファイルが残っています）: {old_path}")
                failed += 1

            # API レート制限対策
            time.sleep(0.5)

    return moved, failed


# ─────────────────────────────────────────────
# メイン
# ─────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="GitHubのフォルダ構造を 地方/都道府県/市区町村 に再編する",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""
変更前:
  miyagi/
    miyagi_sendai_roads.gplb.gz

変更後:
  tohoku/
    miyagi/
      miyagi_sendai/
        miyagi_sendai_roads.gplb.gz

使用例:
  python3 reorganize_github.py --check-only  # 移動先の確認のみ
  python3 reorganize_github.py miyagi        # 宮城県だけ移動
  python3 reorganize_github.py --all         # 全県移動
  python3 reorganize_github.py --dry-run     # 移動内容を確認（実行しない）
""")
    parser.add_argument("prefs",        nargs="*", help="対象都道府県")
    parser.add_argument("--all",        action="store_true", help="全県処理")
    parser.add_argument("--check-only", action="store_true", help="移動先確認のみ")
    parser.add_argument("--dry-run",    action="store_true", help="実行しない")
    parser.add_argument("--list-regions", action="store_true", help="地方区分一覧を表示")
    parser.add_argument("--from", dest="from_pref", metavar="PREF",
                        help="指定した県から残りを実行（途中再開用）")
    args = parser.parse_args()

    if args.list_regions:
        for region, label in REGION_LABELS.items():
            prefs = [k for k,v in REGIONS.items() if v == region]
            print(f"{label:10s} ({region}): {', '.join(prefs)}")
        return

    if args.from_pref:
        if args.from_pref not in PREFECTURES:
            print(f"不明な県名: {args.from_pref}"); sys.exit(1)
        all_keys = list(PREFECTURES.keys())
        start_idx = all_keys.index(args.from_pref)
        targets = all_keys[start_idx:]
        log(f"{args.from_pref} から再開します（残り {len(targets)} 県）")
    elif args.all:
        targets = list(PREFECTURES.keys())
    elif args.prefs:
        targets = args.prefs
    else:
        parser.print_help(); sys.exit(1)

    unknown = [p for p in targets if p not in PREFECTURES]
    if unknown:
        print(f"不明な県名: {unknown}"); sys.exit(1)

    total_moved  = 0
    total_failed = 0

    for pref_key in targets:
        moved, failed = reorganize_prefecture(pref_key, args.check_only, args.dry_run)
        total_moved  += moved
        total_failed += failed

    log(f"\n{'='*50}")
    if args.check_only or args.dry_run:
        log(f"対象ファイル数: {total_moved}")
    else:
        log(f"移動完了: {total_moved} / 失敗: {total_failed}")


if __name__ == "__main__":
    main()

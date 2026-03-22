import os
import glob
from github import Github
from anthropic import Anthropic
import google.generativeai as genai

# ==========================================
# ⚙️ Tier 1 課金版リミッター解除設定
# ==========================================
# ==========================================
# ⚙️ プロジェクト構造・完全指定リスト
# ==========================================
TARGET_PATTERNS = [
    # 1. アプリの入り口と設定
    "lib/main.dart",
    "pubspec.yaml",

    # 2. 画面 (Screens) - 小文字指定 + 保険
    "lib/screens/**/*.dart",
    "lib/screen/**/*.dart",     # 単数形の可能性もケア
    "lib/Screens/**/*.dart",    # Git上の大文字対策

    # 3. サービス (Services) - navigationを明示指定
    "lib/services/**/*.dart",              # services全体
    "lib/services/navigation/**/*.dart",   # ★ここを重点指定

    # 4. 定数 (Constants) - survivalを明示指定
    "lib/constants/**/*.dart",             # constants全体
    "lib/constants/survival/**/*.dart",    # ★ここを重点指定

    # 5. その他の主要フォルダ
    "lib/models/**/*.dart",
    "lib/providers/**/*.dart",
    "lib/controllers/**/*.dart",
    "lib/utils/**/*.dart",
    "lib/widgets/**/*.dart",
    "lib/Widgets/**/*.dart",    # Widgetの大文字対策
]
IGNORE_KEYWORDS = [
    "assets/",    # assetsフォルダ全体
    ".json",      # .jsonファイルすべて
    "test/",      # testフォルダ
]
BRANCH_NAME = "ai-refinement-auto"

def get_all_code():
    code_context = ""
    for pattern in TARGET_PATTERNS:
        files = glob.glob(pattern, recursive=True)
        for f in files:
            # ファイル名が.で始まる場合は除外（例: .env, .gitignore）
            if os.path.basename(f).startswith('.'):
                continue
            # ドットフォルダが含まれる場合は除外（例: .git/, .github/）
            if '/.' in f:
                continue
            # その他のIGNORE_KEYWORDSでチェック
            if any(k in f for k in IGNORE_KEYWORDS):
                continue
            try:
                with open(f, 'r', encoding='utf-8') as file:
                    content = file.read()
                    if len(content) > 10:
                        code_context += f"\n--- FILE: {f} ---\n{content}\n"
            except: pass
    return code_context

def main():
    print("🚀 Paid Tier Mode: Starting Process...")
    
    # API初期化
    genai.configure(api_key=os.environ["GOOGLE_API_KEY"])
    # 最新最強モデルを指定
    gemini = genai.GenerativeModel('gemini-3-pro-preview')
    claude = Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    gh = Github(os.environ["GITHUB_TOKEN"])

    full_code = get_all_code()
    if not full_code:
        print("❌ No code found.")
        return

    # 課金枠を活かし、読み込み量を100万文字（10倍）に拡大
    diagnosis_prompt = f"""
    You are a world-class Flutter architect. 
    Analyze the project and pick ONE file to rewrite based on these ABSOLUTE directives:

    1. UI: Use Navy/Orange palette. BorderRadius 30.0, Height 56.0, Padding 24.0+.
    2. NAV: Implement Waypoint-based navigation (List of LatLng).
    3. LOGIC: Japan=Road width priority. Thailand=Avoid Electric Shock Risk.

    CRITICAL RULE: I want a 100% OVERWRITE for the target file.
    Output ONLY the file path and reason in this format:
    FILE_NAME: [path]
    REASON: [reason]

    Code Base:
    {full_code[:1000000]}
    """
    
    print("🤖 Gemini 3 Pro is scanning whole project...")
    diagnosis = gemini.generate_content(diagnosis_prompt).text
    print(f"Diagnosis: {diagnosis}")
    
    target_file = ""
    for line in diagnosis.split('\n'):
        if "FILE_NAME:" in line:
            target_file = line.split("FILE_NAME:")[1].strip()
            break
            
    if not target_file or not os.path.exists(target_file):
        print(f"⚠️ Target file not found: {target_file}")
        return

    with open(target_file, 'r', encoding='utf-8') as f:
        current_content = f.read()

    print(f"🛠 Claude is generating a high-quality refresh for: {target_file}")
    refine_prompt = f"REWRITE the following file COMPLETELY based on: {diagnosis}\n\nFile: {target_file}\nContent:\n{current_content}\n\nOutput ONLY the full source code in a code block. No conversation."
    
    msg = claude.messages.create(
    model="claude-sonnet-4-5-20250929", # ← 「最新版」という指定に変えます
    max_tokens=8192,
    messages=[{"role": "user", "content": refine_prompt}]
)
    new_code = msg.content[0].text
    new_code = new_code.replace("```dart", "").replace("```json", "").replace("```", "").strip()

    print("📤 Pushing to GitHub...")
    repo = gh.get_repo(os.environ["GITHUB_REPOSITORY"])
    sb = repo.get_branch("main")
    
    try:
        repo.create_git_ref(ref=f"refs/heads/{BRANCH_NAME}", sha=sb.commit.sha)
    except:
        print("Branch already exists.")

    contents = repo.get_contents(target_file, ref=BRANCH_NAME)
    repo.update_file(contents.path, f"AI Refresh: {target_file}", new_code, contents.sha, branch=BRANCH_NAME)
    
    try:
        repo.create_pull(
            title=f"🤖 AI Refresh: {os.path.basename(target_file)}",
            body=f"Directives applied.\n\n{diagnosis}",
            head=BRANCH_NAME,
            base="main"
        )
        print("✅ Pull Request Created!")
    except:
        print("ℹ️ PR updated.")

if __name__ == "__main__":
    main()

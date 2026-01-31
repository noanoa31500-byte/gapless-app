import os
import glob
from github import Github
from anthropic import Anthropic
import google.generativeai as genai

# ==========================================
# ⚙️ GapLess専用 設定エリア
# ==========================================

# 【ホワイトリスト】AIに読ませる「価値のあるファイル」
TARGET_PATTERNS = [
    # 1. アプリの脳みそ（Dartコード全般）
    "lib/**/*.dart",
    
    # 2. 重要な翻訳データ（ピンポイント指定）
    "assets/data/hazard.json", 
    
    # 3. 設計図・権限設定
    "pubspec.yaml",
    "analysis_options.yaml",
    "android/app/src/main/AndroidManifest.xml",
    "ios/Runner/Info.plist",
]

# 【ブラックリスト】AIに絶対に見せないファイル（セキュリティ＆コスト対策）
IGNORE_KEYWORDS = [
    # 🚫 セキュリティ（鍵・環境変数）
    ".env", "key.properties", "google-services.json", "GoogleService-Info.plist",
    ".jks", ".keystore", "firebase_options.dart",
    
    # 🚫 AIノイズ（自動生成ファイル・テスト）
    ".freezed.dart", ".g.dart", "test/",
    
    # 🚫 課金死を防ぐ（地図データ・バイナリ）
    "assets/map_data/", ".geojson", ".topojson", # 地図は絶対NG
    ".png", ".jpg", ".jpeg", ".mp3", ".ttf"
]

# 作業用ブランチ名
BRANCH_NAME = "ai-refinement-auto"

# ==========================================
# 🚀 メインロジック
# ==========================================

# API初期化
genai.configure(api_key=os.getenv("GOOGLE_API_KEY"))
gemini = genai.GenerativeModel('gemini-1.5-pro-latest')
claude = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
gh = Github(os.getenv("GITHUB_TOKEN"))

def is_safe_and_useful(filepath):
    """安全かつ、AIにとって有益なファイルか判定"""
    for keyword in IGNORE_KEYWORDS:
        if keyword in filepath:
            return False
    return True

def get_all_code():
    """指定パターンの全テキストファイルを読み込む"""
    code_context = ""
    count = 0
    
    for pattern in TARGET_PATTERNS:
        # recursive=Trueでサブフォルダも検索
        files = glob.glob(pattern, recursive=True)
        
        for f in files:
            if not is_safe_and_useful(f):
                continue
                
            try:
                with open(f, 'r', encoding='utf-8') as file:
                    content = file.read()
                    # 空ファイルや短すぎるファイルは無視
                    if len(content) < 10: continue
                    
                    code_context += f"\n--- FILE: {f} ---\n{content}\n"
                    count += 1
            except Exception:
                pass # 読めないファイルは静かに無視
            
    print(f"ℹ️ {count} ファイルを読み込みました。")
    return code_context

def main():
    print("🚀 AI自動改善プロセスを開始します (GapLess Mode)...")
    
    # 1. コード読み込み
    full_code = get_all_code()
    if not full_code:
        print("❌ 読み込めるコードが見つかりません。")
        return

    # 2. Geminiによる診断 (全体アーキテクト)
    print("🤖 Gemini: コードベースを分析中...")
    diagnosis_prompt = f"""
    あなたはFlutterアプリ「GapLess（防災アプリ）」のリードアーキテクトです。
    以下のプロジェクトコード全体を分析し、
    「最も改善（リファクタリング・バグ修正・翻訳改善）が必要なファイル」を1つだけ特定してください。
    
    【分析の視点】
    - Dartコード: 可読性、バグの温床、非推奨な書き方
    - hazard.json: タイ語などの翻訳が不自然でないか、緊急時に伝わるか
    - 設定: 権限不足やフォント設定の不備
    
    【禁止事項】
    - 自動生成ファイル(.g.dartなど)は選ばないこと。
    - 設定ファイル(xml, plist, yaml)自体は修正対象にせず、それに関連するDartコードを選ぶこと（翻訳JSONは修正OK）。
    
    出力形式:
    FILE_NAME: [ファイルパス]
    REASON: [改善すべき具体的な理由]
    
    コード:
    {full_code[:800000]} 
    """
    
    try:
        diagnosis = gemini.generate_content(diagnosis_prompt).text
        print(f"📝 Geminiの診断:\n{diagnosis}")
    except Exception as e:
        print(f"Gemini API Error: {e}")
        return
    
    # ファイル名を抽出
    target_file = ""
    for line in diagnosis.split('\n'):
        if "FILE_NAME:" in line:
            target_file = line.split("FILE_NAME:")[1].strip()
            break
            
    if not target_file or not os.path.exists(target_file):
        print(f"⚠️ 対象ファイル {target_file} が特定できませんでした。スキップします。")
        return

    # 対象ファイルの現在の内容を取得
    with open(target_file, 'r', encoding='utf-8') as f:
        current_content = f.read()

    # 3. Claudeによる修正実装 (天才エンジニア)
    print(f"🛠 Claude: {target_file} を修正中...")
    refine_prompt = f"""
    あなたは世界最高峰のFlutterエンジニアです。
    アーキテクトからの指摘に基づき、対象ファイルをリファクタリングしてください。
    
    # アーキテクトの指摘
    {diagnosis}
    
    # 対象ファイル ({target_file})
    {current_content}
    
    # 出力要件
    - 解説は不要です。
    - 修正後の「ファイル全体」を出力してください。
    - 必ずコードブロックで囲ってください。
    - JSONの場合は、JSONの構文エラー（カンマ忘れなど）がないよう注意してください。
    """
    
    try:
        msg = claude.messages.create(
            # 最新最強モデルを指定
            model="claude-sonnet-4-5-20250929",
            max_tokens=4000,
            messages=[{"role": "user", "content": refine_prompt}]
        )
        new_code = msg.content[0].text
    except Exception as e:
        print(f"Claude API Error: {e}")
        return
    
    # コードブロックの除去処理（DartでもJSONでも対応）
    new_code = new_code.replace("```dart", "").replace("```json", "").replace("```yaml", "").replace("```", "").strip()

    # 4. GitHubでPull Request作成
    try:
        repo = gh.get_repo(os.getenv("GITHUB_REPOSITORY"))
        
        # ブランチ作成
        sb = repo.get_branch("main")
        try:
            repo.create_git_ref(ref=f"refs/heads/{BRANCH_NAME}", sha=sb.commit.sha)
        except:
            pass 

        # ファイル更新
        contents = repo.get_contents(target_file, ref=BRANCH_NAME)
        repo.update_file(contents.path, f"AI Refactor: {target_file}", new_code, contents.sha, branch=BRANCH_NAME)
        
        # PR作成
        try:
            pr = repo.create_pull(
                title=f"🤖 AI Refactor: {os.path.basename(target_file)}",
                body=f"GeminiとClaudeによる改善提案です。\n\n**修正理由**:\n{diagnosis}",
                head=BRANCH_NAME,
                base="main"
            )
            print(f"✅ Pull Requestを作成しました: {pr.html_url}")
        except:
            print("ℹ️ PRは既に存在するため、コミットのみ追加しました。")
        
    except Exception as e:
        print(f"GitHub Operation Error: {e}")

if __name__ == "__main__":
    main()
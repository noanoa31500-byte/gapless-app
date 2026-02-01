import os
import glob
from github import Github
from anthropic import Anthropic
import google.generativeai as genai

# ==========================================
# ⚙️ 設定（ここを触る必要はありません）
# ==========================================
TARGET_PATTERNS = ["lib/**/*.dart", "assets/data/hazard.json", "pubspec.yaml"]
IGNORE_KEYWORDS = [".env", "key.properties", "google-services.json", "test/", "assets/map_data/"]
BRANCH_NAME = "ai-refinement-auto"

def get_all_code():
    code_context = ""
    for pattern in TARGET_PATTERNS:
        files = glob.glob(pattern, recursive=True)
        for f in files:
            if any(k in f for k in IGNORE_KEYWORDS): continue
            try:
                with open(f, 'r', encoding='utf-8') as file:
                    content = file.read()
                    if len(content) > 10:
                        code_context += f"\n--- FILE: {f} ---\n{content}\n"
            except: pass
    return code_context

def main():
    print("🚀 Process Start...")
    
    # API初期化（エラーがあればここで止まるように設定）
    genai.configure(api_key=os.environ["GOOGLE_API_KEY"])
    gemini = genai.GenerativeModel('gemini-3-flash-preview')
    claude = Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    gh = Github(os.environ["GITHUB_TOKEN"])

    full_code = get_all_code()
    if not full_code:
        print("❌ No code found.")
        return

    # 【重要】AIへの強制命令を強化
    diagnosis_prompt = f"""
    You are a world-class Flutter architect. 
    Analyze the project and pick ONE file to rewrite based on these ABSOLUTE directives:

    1. UI: Use Navy/Orange palette. BorderRadius 30.0, Height 56.0, Padding 24.0+.
    2. NAV: Implement Waypoint-based navigation (List of LatLng).
    3. LOGIC: Japan=Road width priority. Thailand=Avoid Electric Shock Risk.

    CRITICAL RULE: Do not maintain current code. I want a 100% OVERWRITE for the target file.
    Output ONLY the file path and reason in this format:
    FILE_NAME: [path]
    REASON: [reason]

    Code:
    {full_code[:800000]}
    """
    
    print("🤖 Gemini is diagnosing...")
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

    print(f"🛠 Claude is rewriting: {target_file}")
    refine_prompt = f"REWRITE the following file COMPLETELY based on: {diagnosis}\n\nFile: {target_file}\nContent:\n{current_content}\n\nOutput ONLY the full source code in a code block. No conversation."
    
    msg = claude.messages.create(
        model="claude-4-5-sonnet-20241022",
        max_tokens=8192,
        messages=[{"role": "user", "content": refine_prompt}]
    )
    new_code = msg.content[0].text
    new_code = new_code.replace("```dart", "").replace("```json", "").replace("```", "").strip()

    print("📤 Uploading to GitHub...")
    repo = gh.get_repo(os.environ["GITHUB_REPOSITORY"])
    sb = repo.get_branch("main")
    
    try:
        repo.create_git_ref(ref=f"refs/heads/{BRANCH_NAME}", sha=sb.commit.sha)
    except:
        print("Branch already exists, updating...")

    contents = repo.get_contents(target_file, ref=BRANCH_NAME)
    repo.update_file(contents.path, f"AI Refresh: {target_file}", new_code, contents.sha, branch=BRANCH_NAME)
    
    try:
        repo.create_pull(
            title=f"🤖 AI Refresh: {os.path.basename(target_file)}",
            body=f"Directives applied.\n\n{diagnosis}",
            head=BRANCH_NAME,
            base="main"
        )
        print("✅ PR created successfully!")
    except:
        print("ℹ️ PR already exists.")

if __name__ == "__main__":
    main()

if __name__ == "__main__":
    main()

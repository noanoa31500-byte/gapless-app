import os
import glob
from github import Github
from anthropic import Anthropic
import google.generativeai as genai

# ==========================================
# ⚙️ GapLess専用 設定エリア
# ==========================================

TARGET_PATTERNS = [
    "lib/**/*.dart",
    "assets/data/hazard.json", 
    "pubspec.yaml",
]

IGNORE_KEYWORDS = [
    ".env", "key.properties", "google-services.json", "GoogleService-Info.plist",
    ".jks", ".keystore", "firebase_options.dart",
    ".freezed.dart", ".g.dart", "test/",
    "assets/map_data/", ".geojson", ".topojson",
    ".png", ".jpg", ".jpeg", ".mp3", ".ttf"
]

BRANCH_NAME = "ai-refinement-auto"

# ==========================================
# 🚀 メインロジック
# ==========================================

genai.configure(api_key=os.getenv("GOOGLE_API_KEY"))
gemini = genai.GenerativeModel('gemini-1.5-pro-latest')
claude = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
gh = Github(os.getenv("GITHUB_TOKEN"))

def is_safe_and_useful(filepath):
    for keyword in IGNORE_KEYWORDS:
        if keyword in filepath:
            return False
    return True

def get_all_code():
    code_context = ""
    count = 0
    for pattern in TARGET_PATTERNS:
        files = glob.glob(pattern, recursive=True)
        for f in files:
            if not is_safe_and_useful(f): continue
            try:
                with open(f, 'r', encoding='utf-8') as file:
                    content = file.read()
                    if len(content) < 10: continue
                    code_context += f"\n--- FILE: {f} ---\n{content}\n"
                    count += 1
            except Exception: pass
    return code_context

def main():
    full_code = get_all_code()
    if not full_code: return

    # ここに「指令1〜3」を魂として込めます
SYSTEM_PROMPT = """
You are a world-class Flutter developer. 
Your MISSION is to OVERWRITE the current code to fulfill these goals:

1. DESIGN: Replace standard colors with Navy and Deep Orange. 
   Set BorderRadius to 30.0 for ALL buttons. Maximize padding to 24.0+.
2. LOGIC: Implement dynamic Waypoint navigation using a list of LatLng. 
   The compass must point to the next waypoint.
3. RISK: Japan mode must prioritize road width. Thailand mode must avoid Electric Shock zones.

WARNING: Do not keep the existing code structure. 
I want a COMPLETE REFRESH. If you don't change at least 50% of the file, it is a failure.
"""
    FILE_NAME: [path]
    REASON: [reason]

    Code:
    {full_code[:800000]}
    """
    
    try:
        diagnosis = gemini.generate_content(diagnosis_prompt).text
        print(diagnosis)
    except Exception: return
    
    target_file = ""
    for line in diagnosis.split('\n'):
        if "FILE_NAME:" in line:
            target_file = line.split("FILE_NAME:")[1].strip()
            break
            
    if not target_file or not os.path.exists(target_file): return

    with open(target_file, 'r', encoding='utf-8') as f:
        current_content = f.read()

    refine_prompt = f"""
    Rewrite this file based on the architect's instructions:
    {diagnosis}
    
    Target File: {target_file}
    Current Content:
    {current_content}
    
    Rules: Output the FULL file content in a code block. No explanations.
    """
    
    try:
        msg = claude.messages.create(
            model="claude-3-5-sonnet-20241022",
            max_tokens=4000,
            messages=[{"role": "user", "content": refine_prompt}]
        )
        new_code = msg.content[0].text
    except Exception: return
    
    new_code = new_code.replace("```dart", "").replace("```json", "").replace("```", "").strip()

    try:
        repo = gh.get_repo(os.getenv("GITHUB_REPOSITORY"))
        sb = repo.get_branch("main")
        try:
            repo.create_git_ref(ref=f"refs/heads/{BRANCH_NAME}", sha=sb.commit.sha)
        except: pass 

        contents = repo.get_contents(target_file, ref=BRANCH_NAME)
        repo.update_file(contents.path, f"AI Refresh: {target_file}", new_code, contents.sha, branch=BRANCH_NAME)
        
        repo.create_pull(
            title=f"🤖 AI Refresh: {os.path.basename(target_file)}",
            body=f"Directives applied.\n\n{diagnosis}",
            head=BRANCH_NAME,
            base="main"
        )
    except Exception: pass

if __name__ == "__main__":
    main()

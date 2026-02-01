import os
import glob
from github import Github
from anthropic import Anthropic
import google.generativeai as genai

# ==========================================
# ⚙️ 設定
# ==========================================
TARGET_PATTERNS = ["lib/**/*.dart", "assets/data/hazard.json", "pubspec.yaml"]
IGNORE_KEYWORDS = [".env", "key.properties", "google-services.json", "GoogleService-Info.plist", ".jks", ".keystore", "test/", "assets/map_data/"]
BRANCH_NAME = "ai-refinement-auto"

# ==========================================
# 🚀 ロジック
# ==========================================
genai.configure(api_key=os.getenv("GOOGLE_API_KEY"))
gemini = genai.GenerativeModel('gemini-1.5-pro-latest')
claude = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
gh = Github(os.getenv("GITHUB_TOKEN"))

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
    full_code = get_all_code()
    if not full_code: return

    diagnosis_prompt = f"""
    You are a world-class Flutter architect. 
    Rewrite ONE file based on these ABSOLUTE directives:
    1. UI: Use Navy/Orange, BorderRadius 30.0, Height 56.0, Padding 24.0+.
    2. NAV: Implement Waypoint-based navigation (List of LatLng).
    3. LOGIC: Japan=Road width priority. Thailand=Avoid Electric Shock Risk.
    Do not keep current code. Overwrite significantly.

    FILE_NAME: [path]
    REASON: [reason]

    Code:
    {full_code[:800000]}
    """
    
    try:
        diagnosis = gemini.generate_content(diagnosis_prompt).text
        target_file = ""
        for line in diagnosis.split('\n'):
            if "FILE_NAME:" in line:
                target_file = line.split("FILE_NAME:")[1].strip()
                break
        if not target_file or not os.path.exists(target_file): return

        with open(target_file, 'r', encoding='utf-8') as f:
            current_content = f.read()

        refine_prompt = f"Rewrite this file based on: {diagnosis}\n\nFile: {target_file}\nContent:\n{current_content}\n\nOutput FULL content in code block. No talk."
        msg = claude.messages.create(
            model="claude-3-5-sonnet-20241022",
            max_tokens=4000,
            messages=[{"role": "user", "content": refine_prompt}]
        )
        new_code = msg.content[0].text.replace("```dart", "").replace("```json", "").replace("```", "").strip()

        repo = gh.get_repo(os.getenv("GITHUB_REPOSITORY"))
        sb = repo.get_branch("main")
        try: repo.create_git_ref(ref=f"refs/heads/{BRANCH_NAME}", sha=sb.commit.sha)
        except: pass 

        contents = repo.get_contents(target_file, ref=BRANCH_NAME)
        repo.update_file(contents.path, f"AI Refresh: {target_file}", new_code, contents.sha, branch=BRANCH_NAME)
        
        repo.create_pull(title=f"🤖 AI Refresh: {os.path.basename(target_file)}", body=diagnosis, head=BRANCH_NAME, base="main")
    except: pass

if __name__ == "__main__":
    main()

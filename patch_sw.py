
import os

SW_PATH = 'build/web/flutter_service_worker.js'

FONTS = [
    '"assets/assets/fonts/NotoSansJP-Regular.ttf"',
    '"assets/assets/fonts/NotoSansJP-Bold.ttf"',
    '"assets/assets/fonts/NotoSansThai-Regular.ttf"',
    '"assets/assets/fonts/NotoSansThai-Bold.ttf"'
]

def patch_service_worker():
    if not os.path.exists(SW_PATH):
        print(f"Error: {SW_PATH} not found.")
        return

    with open(SW_PATH, 'r') as f:
        content = f.read()

    # Find the CORE definition
    target_str = '"assets/FontManifest.json"];'
    
    if target_str not in content:
        print("Error: Could not find CORE list end in service worker.")
        # Fallback for different formatting
        if '"assets/FontManifest.json"]' in content:
             target_str = '"assets/FontManifest.json"]'
        else:
             print("Critical Error: CORE pattern not found.")
             print(content[:500]) # Debug
             return

    # Create the injection string
    injection = ',\n' + ',\n'.join(FONTS) + '];'
    
    # Replace
    new_content = content.replace(target_str, '"assets/FontManifest.json"' + injection)
    
    with open(SW_PATH, 'w') as f:
        f.write(new_content)
    
    print("Successfully patched flutter_service_worker.js with fonts.")

if __name__ == "__main__":
    patch_service_worker()

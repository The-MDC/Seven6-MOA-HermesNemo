#!/usr/bin/env python3
"""
One-click deployment script for Seven6-Hermes-MOA orchestration layer.
"""

import os
import shutil
import sys
from pathlib import Path

def main():
    print("🚀 Seven6-Hermes-MOA Deployment Script")
    print("=" * 50)
    
    # Get current directory (should be Seven6-Hermes-MOA workspace)
    current_dir = Path.cwd()
    print(f"📁 Current workspace: {current_dir}")
    
    # Define source and destination paths
    source_dir = current_dir
    hermes_dir = Path.home() / "AppData" / "Local" / "hermes"
    
    # Check if Hermes directory exists
    if not hermes_dir.exists():
        print(f"❌ Hermes directory not found: {hermes_dir}")
        print("Please ensure Hermes Agent is installed.")
        return 1
    
    print(f"📦 Target Hermes directory: {hermes_dir}")
    
    # Copy hermes-skills
    source_skills = source_dir / "hermes-skills"
    target_skills = hermes_dir / "hermes-skills"
    if source_skills.exists():
        print(f"📋 Copying skills: {source_skills} → {target_skills}")
        if target_skills.exists():
            shutil.rmtree(target_skills)
        shutil.copytree(source_skills, target_skills)
        print("✅ Skills copied successfully")
    else:
        print(f"❌ Source skills directory not found: {source_skills}")
        return 1
    
    # Copy seven6-orchestration
    source_orchestration = source_dir / "seven6-orchestration"
    target_orchestration = hermes_dir / "seven6-orchestration"
    if source_orchestration.exists():
        print(f"⚙️  Copying orchestration: {source_orchestration} → {target_orchestration}")
        if target_orchestration.exists():
            shutil.rmtree(target_orchestration)
        shutil.copytree(source_orchestration, target_orchestration)
        print("✅ Orchestration copied successfully")
    else:
        print(f"❌ Source orchestration directory not found: {source_orchestration}")
        return 1
    
    # Copy seven6-moa
    source_moa = source_dir / "seven6-moa"
    target_moa = hermes_dir / "seven6-moa"
    if source_moa.exists():
        print(f"💾 Copying MOA components: {source_moa} → {target_moa}")
        if target_moa.exists():
            shutil.rmtree(target_moa)
        shutil.copytree(source_moa, target_moa)
        print("✅ MOA components copied successfully")
    else:
        print(f"❌ Source MOA directory not found: {source_moa}")
        return 1
    
    # Copy consistency-verification-skill
    source_consistency = source_dir / "consistency-verification-skill"
    target_consistency = hermes_dir / "hermes-skills" / "consistency-verification-skill"
    if source_consistency.exists():
        print(f"📜 Copying consistency skill: {source_consistency} → {target_consistency}")
        if target_consistency.exists():
            shutil.rmtree(target_consistency)
        shutil.copytree(source_consistency, target_consistency)
        print("✅ Consistency skill copied successfully")
    else:
        print(f"❌ Source consistency skill not found: {source_consistency}")
        return 1
    
    # Create requirements.txt if it doesn't exist in target
    target_requirements = hermes_dir / "requirements.txt"
    source_requirements = source_dir / "requirements.txt"
    if source_requirements.exists():
        shutil.copy2(source_requirements, target_requirements)
        print("📋 Requirements file copied")
    elif not target_requirements.exists():
        # Create basic requirements.txt
        with open(target_requirements, 'w') as f:
            f.write("# Seven6-Hermes-MOA Requirements\n")
            f.write("# Add your project-specific requirements here\n")
        print("📋 Created basic requirements.txt")
    
    # Create a simple verification script
    verify_script = hermes_dir / "verify_deployment.py"
    with open(verify_script, 'w') as f:
        f.write('''#!/usr/bin/env python3
"""Verification script for Seven6-Hermes-MOA deployment."""

import sys
from pathlib import Path

def main():
    hermes_dir = Path.home() / "AppData" / "Local" / "hermes"
    
    print("🔍 Verifying Seven6-Hermes-MOA deployment...")
    
    # Check skills directory
    skills_dir = hermes_dir / "hermes-skills"
    if not skills_dir.exists():
        print("❌ Skills directory not found")
        return 1
    
    skill_count = len([d for d in skills_dir.iterdir() if d.is_dir() and (d / "SKILL.md").exists()])
    print(f"📊 Found {skill_count} skills")
    
    # Check for seven6-port in a sample skill
    sample_skill = skills_dir / "noesis-qwen3-tts" / "SKILL.md"
    if sample_skill.exists():
        content = sample_skill.read_text()
        if "source: seven6-port" in content:
            print("✅ seven6-port metadata verified")
        else:
            print("❌ seven6-port metadata missing")
            return 1
    else:
        print("⚠️  Sample skill not found for verification")
    
    # Check orchestration directory
    orchestration_dir = hermes_dir / "seven6-orchestration"
    if orchestration_dir.exists():
        print("✅ Orchestration directory found")
    else:
        print("❌ Orchestration directory missing")
        return 1
    
    # Check MOA directory
    moa_dir = hermes_dir / "seven6-moa"
    if moa_dir.exists():
        print("✅ MOA directory found")
    else:
        print("❌ MOA directory missing")
        return 1
    
    print("🎉 Deployment verification successful!")
    print("🚀 Seven6-Hermes-MOA is ready for use!")
    return 0

if __name__ == "__main__":
    sys.exit(main())
''')
    
    # Make verification script executable on Unix-like systems
    if os.name != 'nt':  # Not Windows
        os.chmod(verify_script, 0o755)
    
    print("🔧 Created verification script: verify_deployment.py")
    
    print("\n" + "=" * 50)
    print("✅ Deployment completed successfully!")
    print("📋 Next steps:")
    print("   1. Restart Hermes Agent to load new skills")
    print("   2. Run verification: python verify_deployment.py")
    print("   3. Test with: python -c \"from seven6_orchestration import orchestrate; print('Ready!')\"")
    print("=" * 50)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())

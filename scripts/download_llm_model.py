#!/usr/bin/env python3
"""
Download Qwen2-VL-2B-Instruct-4bit model from HuggingFace to LLM folder.
Run as Xcode Build Script Phase.
"""

import os
import sys
from pathlib import Path

# 安装 huggingface_hub 如果需要
try:
    from huggingface_hub import snapshot_download
except ImportError:
    print("Installing huggingface_hub...")
    os.system("pip3 install huggingface_hub -q")
    from huggingface_hub import snapshot_download

# 模型ID
MODEL_ID = "Qwen/Qwen2-VL-2B-Instruct-4bit"

# 目标文件夹 - 从脚本参数获取或者使用默认的LLM路径
if len(sys.argv) > 1:
    target_dir = Path(sys.argv[1])
else:
    # 默认: 项目目录下的 HeartBeatMemory/LLM
    script_dir = Path(os.path.dirname(os.path.abspath(__file__)))
    project_dir = script_dir.parent.parent
    target_dir = project_dir / "HeartBeatMemory" / "LLM" / "Qwen2-VL-2B-Instruct-4bit"

print(f"Downloading {MODEL_ID} to {target_dir}...")

try:
    # 下载模型（忽略已存在的文件）
    local_dir = snapshot_download(
        repo_id=MODEL_ID,
        local_dir=target_dir,
        ignore_patterns=[".git*"],  # 忽略 git 文件
        resume_download=True,
    )
    print(f"✓ Model downloaded to: {local_dir}")
    sys.exit(0)
except Exception as e:
    print(f"✗ Error: {e}", file=sys.stderr)
    sys.exit(1)
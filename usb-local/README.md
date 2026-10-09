# usb-local

Offline screen helper. After the files are on the USB, start.bat only listens on 127.0.0.1.

Ctrl+Shift and left-drag a box. Click the popup or press Esc to close it. Ctrl+Shift+Q quits x.exe. Close the llama-server window to stop the model.

## What goes in this folder

- x.exe
- start.bat
- llama-server.exe and the DLLs from a current llama.cpp Windows build
- model.gguf
- mmproj.gguf, only if the build ships a separate projector

## Model

Use Qwen3.8-27B, the newer native vision Qwen. BF16 is about 55 GB, so it fits on a 114 GB stick with room for the runtime. That is higher quality than the older Qwen2.5-VL-72B Q4 file.

- https://huggingface.co/unsloth/Qwen3.8-27B-GGUF
- download the BF16 file and rename it model.gguf
- if that repo also has an mmproj file, rename it mmproj.gguf
- llama.cpp Windows binaries: https://github.com/ggml-org/llama.cpp/releases

Use a llama.cpp build new enough to list qwen3.8 / qwen35. If BF16 is too slow, use Q8_0 from the same repo (about 29 GB) and keep the filename model.gguf.

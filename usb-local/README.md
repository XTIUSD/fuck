# usb-local

Offline screen helper. After the files are on the USB, start.bat only listens on 127.0.0.1.

Ctrl+Shift and left-drag a box. Click the popup or press Esc to close it. Ctrl+Shift+Q quits x.exe. Close the llama-server window to stop the model.

## What goes in this folder

- x.exe
- start.bat
- llama-server.exe and the DLLs from the same llama.cpp Windows build
- model.gguf
- mmproj.gguf

## Model

Best free vision Qwen that fits on a 114 GB stick: Qwen2.5-VL-72B-Instruct at Q4_K_M, about 40 GB plus a projector file of about 1 GB. A 16-bit 72B does not fit. GitHub rejects files over 100 MB, so the weights are not in this repo.

Download once on a network, then copy the folder to the USB:

- model: https://huggingface.co/mradermacher/Qwen2.5-VL-72B-Instruct-GGUF
- use the Q4_K_M file and rename it model.gguf
- mmproj: the matching mmproj file from that repo, renamed mmproj.gguf
- llama.cpp Windows binaries: https://github.com/ggml-org/llama.cpp/releases

If 72B is too slow on CPU, use Qwen2.5-VL-7B-Instruct Q4_K_M instead (about 5 GB). Same filenames.

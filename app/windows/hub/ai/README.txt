LiveNow AI helpers (receipt assistant), for the hub PC
======================================================

Two local services, both on 127.0.0.1 only (nothing leaves the PC, no cloud):
  1. OCR service  (ocr_service.py, port 47655)  RapidOCR, Tesseract as fallback
  2. Text model   Ollama (port 11434), default model qwen2.5:3b-instruct

Install:    double-click install_ai.cmd  (UAC prompt once; needs Python 3.9-3.12 and Ollama)
            install_ai.ps1 -Model "<ollama model name>" -Port 47655  to change the defaults
Remove:     uninstall_ai.cmd             (keeps Ollama and its models)
Try by hand: start_ai.cmd                (OCR service in a console, no task)
Check:      http://127.0.0.1:47655/health   and   http://127.0.0.1:11434/v1/models

Memory (hub PC: CPU only, 8 GB RAM)
  - OCR and the model run one AFTER the other, never together (the hub app sequences them).
  - Ollama unloads the model 1 minute after use (OLLAMA_KEEP_ALIVE=1m, set by install_ai.ps1;
    restart Ollama once to apply). One model, one request at a time.
  - Expect minutes per receipt on CPU; the app waits (generous timeouts) and shows progress.
  - The model names and URLs are hub settings, not code: a different model needs no phone update.

OCR notes
  - Engine: LIVENOW_OCR_ENGINE=auto (default) | rapidocr | tesseract.
  - RapidOCR's default models handle Latin text but can drop Turkish diacritics. For better results
    download a Latin recognition model (ONNX) and its key file yourself and set
    LIVENOW_OCR_REC_MODEL / LIVENOW_OCR_REC_KEYS (user environment variables) before the task starts.
  - Tesseract needs the program itself plus tur.traineddata (set TESSERACT_CMD if it is not on PATH).
  - LIVENOW_OCR_DESKEW=1 straightens tilted photos (needs OpenCV, which RapidOCR installs).
  - Reply format (POST /ocr, body = raw image bytes):
      {"engine": "...", "width": W, "height": H,
       "lines": [{"text": "KURU KAYISI  32,50", "box": [x0, y0, x1, y1], "confidence": 0.93}]}
    One entry per printed row, top to bottom, words left to right.
  - Log: %LOCALAPPDATA%\LiveNowHub\ai\ocr.log

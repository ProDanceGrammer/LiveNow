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
  - Recognition models (install_ai.ps1 downloads them into ai\models, sha256 checked, skipped when
    present; PP-OCRv5 mobile ONNX from Hugging Face monkt/paddleocr-onnx, Apache-2.0):
      latin_rec.onnx + latin_dict.txt   Latin incl. Turkish letters = the DEFAULT reading (no ?lang=)
      eslav_rec.onnx + eslav_dict.txt   Ukrainian/Russian/Belarusian + Latin = POST /ocr?lang=uk
    One text detector, one recogniser per language; the Ukrainian one is loaded on first use. The hub
    app reads a photo with the default model and, when it looks like a bank screenshot, once more
    with lang=uk. GET /health lists the languages: {"langs": ["default", "uk"], "default_rec": "latin"}.
    Receipts are never read twice. Missing files: the stock RapidOCR model (Chinese+English, no
    Cyrillic) is the default and "uk" is not offered.
  - LIVENOW_OCR_DEFAULT_REC=latin (default) | stock picks the default reading's model.
    Overrides: LIVENOW_OCR_MODELS_DIR, LIVENOW_OCR_REC_LATIN / _KEYS, LIVENOW_OCR_REC_UK / _KEYS;
    the old LIVENOW_OCR_REC_MODEL / _KEYS still replace the stock default.
  - Tesseract needs the program itself plus tur.traineddata (set TESSERACT_CMD if it is not on PATH).
  - LIVENOW_OCR_DESKEW=1 straightens tilted photos (needs OpenCV, which RapidOCR installs).
  - Reply format (POST /ocr, body = raw image bytes):
      {"engine": "...", "width": W, "height": H,
       "lines": [{"text": "KURU KAYISI  32,50", "box": [x0, y0, x1, y1], "confidence": 0.93}]}
    (?lang=uk: the same reply read with the Ukrainian recogniser.)
    One entry per printed row, top to bottom, words left to right.
  - Log: %LOCALAPPDATA%\LiveNowHub\ai\ocr.log

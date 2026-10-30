"""LiveNow local OCR service (runs next to the hub, listens on 127.0.0.1 only).

  GET  /health  -> {"ok": true, "engine": "rapidocr" | "tesseract"}
  POST /ocr     -> body = the raw image bytes (JPEG/PNG/...)
                   reply = {"engine", "width", "height",
                            "lines": [{"text", "box": [x0, y0, x1, y1], "confidence"}]}
                   one entry per printed ROW: words on the same baseline are joined left to
                   right, rows are ordered top to bottom (reading order).

Engine: RapidOCR (rapidocr_onnxruntime) when installed, else Tesseract (pytesseract, languages
tur+eng). Force one with LIVENOW_OCR_ENGINE=rapidocr|tesseract. RapidOCR's stock models know
Latin letters but not every Turkish diacritic; point LIVENOW_OCR_REC_MODEL (+ optional
LIVENOW_OCR_REC_KEYS) at a Latin recognition model file to improve that (see README.txt).

Only the standard library is required to START; the engines and Pillow are imported lazily.
One image is processed at a time (a lock): the hub PC has little RAM.
"""
import argparse
import io
import json
import logging
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = logging.getLogger("livenow-ocr")
MAX_BODY = int(os.environ.get("LIVENOW_OCR_MAX_BYTES", 25 * 1024 * 1024))
MAX_SIDE = int(os.environ.get("LIVENOW_OCR_MAX_SIDE", 2000))
DESKEW = os.environ.get("LIVENOW_OCR_DESKEW", "0") == "1"
_lock = threading.Lock()
_engine = None  # (name, callable(PIL.Image) -> [(x0, y0, x1, y1, text, conf)])


def _load_engine():
    want = os.environ.get("LIVENOW_OCR_ENGINE", "auto").lower()
    if want in ("auto", "rapidocr"):
        try:
            from rapidocr_onnxruntime import RapidOCR  # type: ignore

            kwargs = {}
            if os.environ.get("LIVENOW_OCR_REC_MODEL"):
                kwargs["rec_model_path"] = os.environ["LIVENOW_OCR_REC_MODEL"]
            if os.environ.get("LIVENOW_OCR_REC_KEYS"):
                kwargs["rec_keys_path"] = os.environ["LIVENOW_OCR_REC_KEYS"]
            rapid = RapidOCR(**kwargs)

            def run(img):
                import numpy as np  # type: ignore

                result, _ = rapid(np.array(img))
                out = []
                for box, text, conf in result or []:
                    xs = [p[0] for p in box]
                    ys = [p[1] for p in box]
                    out.append((min(xs), min(ys), max(xs), max(ys), str(text), float(conf)))
                return out

            return "rapidocr", run
        except Exception as e:  # not installed or broken: fall back
            LOG.warning("RapidOCR unavailable (%s)", e)
            if want == "rapidocr":
                raise
    import pytesseract  # type: ignore

    cmd = os.environ.get("TESSERACT_CMD")
    if cmd:
        pytesseract.pytesseract.tesseract_cmd = cmd
    langs = os.environ.get("LIVENOW_OCR_TESS_LANGS", "tur+eng")

    def run(img):
        d = pytesseract.image_to_data(img, lang=langs, config="--psm 6",
                                      output_type=pytesseract.Output.DICT)
        out = []
        for i, text in enumerate(d["text"]):
            if not text.strip():
                continue
            try:
                conf = float(d["conf"][i]) / 100.0
            except ValueError:
                conf = 0.0
            if conf < 0:
                continue
            x, y, w, h = d["left"][i], d["top"][i], d["width"][i], d["height"][i]
            out.append((x, y, x + w, y + h, text, conf))
        return out

    return "tesseract", run


def get_engine():
    global _engine
    if _engine is None:
        _engine = _load_engine()
    return _engine


def preprocess(data):
    """EXIF-rotate, flatten to RGB, cap the long side, optional deskew."""
    from PIL import Image, ImageOps  # type: ignore

    img = Image.open(io.BytesIO(data))
    img = ImageOps.exif_transpose(img).convert("RGB")
    long_side = max(img.size)
    if long_side > MAX_SIDE:
        k = MAX_SIDE / long_side
        img = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
    if DESKEW:
        img = _deskew(img)
    return img


def _deskew(img):
    """Straighten small tilts (needs OpenCV, which RapidOCR installs); silently skipped otherwise."""
    try:
        import cv2  # type: ignore
        import numpy as np  # type: ignore
        from PIL import Image  # type: ignore

        gray = cv2.cvtColor(np.array(img), cv2.COLOR_RGB2GRAY)
        pts = np.column_stack(np.where(cv2.threshold(gray, 0, 255,
                                                     cv2.THRESH_BINARY_INV | cv2.THRESH_OTSU)[1] > 0))
        if len(pts) < 100:
            return img
        angle = cv2.minAreaRect(pts.astype("float32"))[-1]
        angle = -(90 + angle) if angle < -45 else -angle
        if abs(angle) < 0.5 or abs(angle) > 15:
            return img
        h, w = gray.shape
        m = cv2.getRotationMatrix2D((w / 2, h / 2), angle, 1.0)
        rot = cv2.warpAffine(np.array(img), m, (w, h), flags=cv2.INTER_CUBIC,
                             borderMode=cv2.BORDER_REPLICATE)
        return Image.fromarray(rot)
    except Exception as e:
        LOG.warning("deskew skipped (%s)", e)
        return img


def group_rows(items):
    """Join word boxes into printed rows: top to bottom, left to right inside a row."""
    if not items:
        return []
    heights = sorted(it[3] - it[1] for it in items)
    row_h = max(1.0, heights[len(heights) // 2])
    items = sorted(items, key=lambda it: (it[1] + it[3]) / 2)
    rows, cur, cur_y = [], [], None
    for it in items:
        cy = (it[1] + it[3]) / 2
        if cur and abs(cy - cur_y) > 0.6 * row_h:
            rows.append(cur)
            cur = []
        cur.append(it)
        cur_y = sum((c[1] + c[3]) / 2 for c in cur) / len(cur)
    if cur:
        rows.append(cur)
    out = []
    for row in rows:
        row.sort(key=lambda it: it[0])
        out.append({
            "text": "  ".join(it[4] for it in row),
            "box": [round(min(it[0] for it in row)), round(min(it[1] for it in row)),
                    round(max(it[2] for it in row)), round(max(it[3] for it in row))],
            "confidence": round(sum(it[5] for it in row) / len(row), 3),
        })
    return out


def run_ocr(data):
    name, run = get_engine()
    img = preprocess(data)
    with _lock:
        items = run(img)
    return {"engine": name, "width": img.width, "height": img.height,
            "lines": group_rows(items)}


class Handler(BaseHTTPRequestHandler):
    server_version = "LiveNowOCR/1"

    def log_message(self, fmt, *args):  # route http.server's log to logging
        LOG.info("%s %s", self.address_string(), fmt % args)

    def _send(self, status, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path != "/health":
            return self._send(404, {"error": "not found"})
        try:
            self._send(200, {"ok": True, "engine": get_engine()[0]})
        except Exception as e:
            self._send(503, {"ok": False, "error": str(e)})

    def do_POST(self):
        if self.path != "/ocr":
            return self._send(404, {"error": "not found"})
        try:
            n = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            n = 0
        if n <= 0 or n > MAX_BODY:
            return self._send(413 if n > MAX_BODY else 400, {"error": "bad body size"})
        data = self.rfile.read(n)
        try:
            self._send(200, run_ocr(data))
        except Exception as e:
            LOG.exception("ocr failed")
            self._send(500, {"error": str(e)})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=47655)
    ap.add_argument("--log", default=None, help="log file (pythonw has no console)")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, filename=args.log,
                        format="%(asctime)s %(levelname)s %(message)s")
    # Loopback only: the hub app on this PC is the sole client.
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    LOG.info("OCR service on 127.0.0.1:%d", args.port)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()


if __name__ == "__main__":
    sys.exit(main())

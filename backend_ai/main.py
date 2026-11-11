from __future__ import annotations

import io
import re
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, UnidentifiedImageError
from ultralytics import YOLO


BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "best.onnx"

app = FastAPI(title="Money Identifier AI", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    # The backend is intended to stay on the laptop/local network.
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

model: YOLO | None = None

# Rates from Bang_Ty_Gia_Ngoai_Te_Full.xlsx, expressed as VND for one unit
# of each currency. Cross-rates are calculated from these reference values.
VND_PER_UNIT: dict[str, Decimal] = {
    "USD": Decimal("25500"),
    "EUR": Decimal("28500"),
    "CNY": Decimal("3800"),
    "JPY": Decimal("160"),
    "THB": Decimal("750"),
    "TRY": Decimal("515"),
    "INR": Decimal("275"),
    "KRW": Decimal("18.5"),
    "KHR": Decimal("6.3"),
    "VND": Decimal("1"),
}
NO_DECIMAL_CURRENCIES = {"VND", "KRW", "JPY", "KHR"}
EXCHANGE_DISPLAY_UNITS = {
    "VND": Decimal("1000"),
    "KRW": Decimal("1000"),
    "KHR": Decimal("1000"),
    "JPY": Decimal("100"),
}


def format_amount(value: Decimal, currency: str) -> str:
    decimals = 0 if currency in NO_DECIMAL_CURRENCIES else 2
    quantum = Decimal("1") if decimals == 0 else Decimal("0.01")
    rounded = value.quantize(quantum, rounding=ROUND_HALF_UP)
    formatted = f"{rounded:,.{decimals}f}"
    if decimals == 0:
        formatted = formatted.replace(",", ".")
    return f"{formatted} {currency}"


@app.on_event("startup")
def load_model() -> None:
    global model
    if not MODEL_PATH.is_file():
        raise RuntimeError(f"Không tìm thấy model ONNX: {MODEL_PATH}")
    # Keep a single loaded model for all requests. Resolve the path independently
    # of the shell's current working directory (Flutter/VS Code launch location).
    model = YOLO(str(MODEL_PATH), task="detect")
    print(f"Đã tải model: {MODEL_PATH}")


@app.get("/")
def health() -> dict[str, Any]:
    return {"status": "ok", "model_loaded": model is not None, "model": MODEL_PATH.name}


def currency_from_label(label: str) -> str | None:
    prefix = label.strip().lower().split("_", 1)[0]
    return {
        "cbr": "KHR",  # Cambodian riel labels in this model.
        "cny": "CNY",
        "ndt": "CNY",  # Chinese renminbi labels in this model.
        "eur": "EUR",
        "inr": "INR",
        "jpy": "JPY",
        "krw": "KRW",
        "thb": "THB",
        "try": "TRY",
        "usd": "USD",
        "vnd": "VND",
        "yen": "JPY",
    }.get(prefix)


def denomination_from_label(label: str) -> int | None:
    """Parse model classes such as vnd_50k, krw_10k and usd_10."""
    normalized = label.strip().lower().replace(",", "")
    match = re.search(r"_(\d+(?:\.\d+)?)\s*([km]?)", normalized)
    if not match:
        return None
    value = float(match.group(1))
    suffix = match.group(2).lower()
    if suffix == "k":
        value *= 1_000
    elif suffix == "m":
        value *= 1_000_000
    return int(value)


@app.post("/predict")
async def predict_currency(
    file: UploadFile = File(...),
    from_currency: str = Form("VND"),
    to_currency: str = Form("USD"),
    confidence_threshold: float = Form(0.25),
    overlap_threshold: float = Form(0.45),
) -> dict[str, Any]:
    if model is None:
        raise HTTPException(status_code=503, detail="Model ONNX chưa được tải.")

    image_bytes = await file.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Ảnh tải lên đang trống.")
    try:
        image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    except (UnidentifiedImageError, OSError) as exc:
        raise HTTPException(status_code=400, detail="File tải lên không phải ảnh hợp lệ.") from exc

    confidence_threshold = min(1.0, max(0.01, confidence_threshold))
    overlap_threshold = min(1.0, max(0.01, overlap_threshold))
    results = model.predict(
        image, conf=confidence_threshold, iou=overlap_threshold, verbose=False
    )
    result = results[0]
    boxes = result.boxes
    if boxes is None or len(boxes) == 0:
        return {
            "detected_label": "Không nhận diện được tờ tiền",
            "converted_amount": "0",
            "exchange_rate": "-",
            "confidence": 0.0,
            "count": 0,
            "total_detected": 0,
            "security_check": "Không phát hiện tờ tiền trong ảnh",
        }

    names = result.names
    detections: list[dict[str, Any]] = []
    totals_by_currency: dict[str, int] = {}
    confidences: list[float] = []
    for box in boxes:
        class_id = int(box.cls[0].item())
        confidence = float(box.conf[0].item())
        label = str(names[class_id])
        currency = currency_from_label(label)
        value = denomination_from_label(label)
        if currency is None or value is None:
            continue
        totals_by_currency[currency] = totals_by_currency.get(currency, 0) + value
        confidences.append(confidence)
        x1, y1, x2, y2 = (float(value) for value in box.xyxy[0].tolist())
        detections.append({
            "label": label,
            "currency": currency,
            "value": value,
            "confidence": round(confidence, 4),
            "box": [round(x1 / image.width, 6), round(y1 / image.height, 6),
                    round(x2 / image.width, 6), round(y2 / image.height, 6)],
        })

    if not detections:
        return {
            "detected_label": "Không đọc được mệnh giá",
            "converted_amount": "0",
            "exchange_rate": "-",
            "confidence": 0.0,
            "count": 0,
            "total_detected": 0,
            "security_check": "Có vật thể được phát hiện nhưng nhãn không chứa mệnh giá",
        }

    actual_currencies = list(totals_by_currency)
    detected_currency = actual_currencies[0] if len(actual_currencies) == 1 else "MIXED"
    detected_text = " + ".join(
        format_amount(Decimal(value), currency)
        for currency, value in totals_by_currency.items()
    )

    target_currency = to_currency.upper()
    converted_total = Decimal("0")
    conversion_supported = target_currency in VND_PER_UNIT
    for source_currency, amount in totals_by_currency.items():
        source_rate = VND_PER_UNIT.get(source_currency)
        target_rate = VND_PER_UNIT.get(target_currency)
        if source_rate is None or target_rate is None:
            conversion_supported = False
            break
        converted_total += Decimal(amount) * source_rate / target_rate

    if conversion_supported:
        converted_text = format_amount(converted_total, target_currency)
        if len(actual_currencies) == 1:
            source_currency = actual_currencies[0]
            display_unit = EXCHANGE_DISPLAY_UNITS.get(
                source_currency, Decimal("1")
            )
            exchange_rate = (
                f"{format_amount(display_unit, source_currency)} = "
                f"{format_amount(display_unit * VND_PER_UNIT[source_currency] / VND_PER_UNIT[target_currency], target_currency)}"
            )
        else:
            exchange_rate = "Đã quy đổi riêng từng loại tiền theo bảng tỷ giá."
    else:
        converted_text = f"Chưa hỗ trợ quy đổi sang {target_currency}."
        exchange_rate = "Cặp tiền tệ chưa có trong bảng tỷ giá."

    selected_source = from_currency.upper()
    currencies_match_selection = all(currency == selected_source for currency in actual_currencies)
    if currencies_match_selection:
        security_message = "Đã nhận diện bằng model ONNX; ứng dụng không xác thực tiền thật hay giả."
    else:
        security_message = (
            f"Model nhận diện {', '.join(actual_currencies)}; "
            f"bạn đã chọn {selected_source}. Phép quy đổi dùng loại tiền AI nhận diện."
        )

    return {
        "detected_label": detected_text,
        "converted_amount": converted_text,
        "exchange_rate": exchange_rate,
        "confidence": round(sum(confidences) / len(confidences), 4),
        "count": len(detections),
        "detected_currency": detected_currency,
        "selected_source_currency": selected_source,
        "currency_match": currencies_match_selection,
        "currency_totals": totals_by_currency,
        "total_detected": totals_by_currency[actual_currencies[0]] if len(actual_currencies) == 1 else None,
        "detections": detections,
        "image_width": image.width,
        "image_height": image.height,
        "confidence_threshold": confidence_threshold,
        "overlap_threshold": overlap_threshold,
        "security_check": security_message,
    }

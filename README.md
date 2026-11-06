# Money Identifier AI

Ứng dụng Flutter giúp chụp/chọn ảnh tiền giấy, gửi ảnh đến backend FastAPI để nhận diện bằng mô hình YOLO ONNX, đếm mệnh giá và quy đổi tổng tiền theo bảng tỷ giá cố định trong mã nguồn.

## Mục lục

- [Tổng quan kiến trúc](#tổng-quan-kiến-trúc)
- [Luồng hoạt động](#luồng-hoạt-động)
- [Cấu trúc dự án](#cấu-trúc-dự-án)
- [Yêu cầu](#yêu-cầu)
- [Cài đặt và chạy backend](#cài-đặt-và-chạy-backend)
- [Chạy ứng dụng Flutter](#chạy-ứng-dụng-flutter)
- [Kết nối frontend với backend](#kết-nối-frontend-với-backend)
- [API](#api)
- [Định dạng phản hồi](#định-dạng-phản-hồi)
- [Cách tính kết quả](#cách-tính-kết-quả)
- [Lỗi thường gặp](#lỗi-thường-gặp)
- [Giới hạn và lưu ý](#giới-hạn-và-lưu-ý)

## Tổng quan kiến trúc

```text
Người dùng
   │ chụp ảnh bằng camera hoặc chọn ảnh từ thư viện
   ▼
Flutter frontend (lib/)
   │ HTTP GET / để kiểm tra backend
   │ HTTP multipart POST /predict để gửi ảnh và tùy chọn tiền tệ
   ▼
FastAPI backend (backend_ai/main.py)
   │ Pillow giải mã ảnh → YOLO/ONNX phát hiện các tờ tiền
   │ đọc nhãn lớp → xác định loại tiền/mệnh giá → cộng và quy đổi
   ▼
JSON response
   │
   ▼
Flutter giải mã JSON và hiển thị kết quả/khung phát hiện trên ảnh
```

Frontend và backend là hai tiến trình riêng, giao tiếp qua HTTP. Flutter không nạp mô hình ONNX trực tiếp. Backend tải mô hình một lần khi khởi động và tái sử dụng mô hình cho các yêu cầu nhận diện tiếp theo. Ảnh và kết quả chỉ được giữ trong trạng thái của phiên ứng dụng; dự án hiện không có API lưu lịch sử hay cơ sở dữ liệu.

## Luồng hoạt động

1. Flutter khởi chạy giao diện trong `lib/main.dart`, sau đó hiển thị ứng dụng được xây dựng trong `lib/money_identifier_app.dart`.
2. Frontend chọn địa chỉ backend từ `API_BASE_URL` nếu được cấu hình; nếu không, ứng dụng chọn địa chỉ mặc định theo nền tảng.
3. Ứng dụng gọi `GET /` để cập nhật trạng thái backend. Backend báo sẵn sàng khi HTTP trả `200` và `model_loaded` là `true`.
4. Người dùng chọn tiền tệ nguồn/đích, sau đó chụp ảnh hoặc chọn ảnh từ thư viện. Luồng camera dùng plugin `camera`; luồng thư viện dùng `image_picker`. Ảnh được giới hạn tối đa 1600 × 1600 và chất lượng 90 ở thao tác chọn ảnh.
5. Flutter gửi ảnh cùng hai loại tiền và hai ngưỡng nhận diện qua `POST /predict` dưới dạng `multipart/form-data`. Yêu cầu có thời hạn chờ 90 giây.
6. FastAPI đọc ảnh, chuyển sang RGB và gọi YOLO với ngưỡng confidence/IoU. Mỗi detection hợp lệ được ánh xạ từ tên lớp của mô hình thành loại tiền và mệnh giá.
7. Backend gom tổng theo từng loại tiền, tính giá trị quy đổi bằng bảng tỷ giá trong `backend_ai/main.py`, rồi trả JSON.
8. Flutter giải mã JSON, chuyển sang trang kết quả, hiển thị tổng nhận diện/quy đổi và các detection tương ứng. Nếu yêu cầu thất bại, ứng dụng hiển thị lỗi kết nối hoặc lỗi HTTP.

## Cấu trúc dự án

| Đường dẫn | Vai trò |
| --- | --- |
| `lib/main.dart` | Điểm vào Flutter, khởi tạo `MaterialApp`. |
| `lib/money_identifier_app.dart` | Giao diện, điều hướng các trang, camera/thư viện ảnh, chọn tiền tệ, gọi API và hiển thị kết quả. |
| `backend_ai/main.py` | FastAPI, tải model, nhận ảnh, suy luận, tính tổng và quy đổi. |
| `backend_ai/best.onnx` | Model ONNX được backend nạp lúc khởi động. |
| `backend_ai/requirements.txt` | Thư viện Python cần cho API và suy luận. |
| `dev.ps1` | Hỗ trợ chạy backend nếu chưa sẵn sàng, chờ model tải xong rồi chạy Flutter Web trên Edge. |
| `pubspec.yaml` | Khai báo Flutter dependencies như `http`, `camera`, `image_picker`. |

## Yêu cầu

- Flutter SDK và Dart tương thích với phiên bản khai báo trong `pubspec.yaml`.
- Python, `pip`, và PowerShell nếu chạy script `dev.ps1`.
- Model `backend_ai/best.onnx` phải tồn tại. Model không được tự tải bởi API.
- Thiết bị/trình giả lập cần quyền camera nếu dùng chức năng chụp ảnh.

## Cài đặt và chạy backend

Mở PowerShell tại thư mục gốc dự án:

```powershell
cd backend_ai
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8080 --reload
```

Backend nạp `backend_ai/best.onnx` trong startup. Đường dẫn model được xác định theo vị trí file `main.py`, không phụ thuộc thư mục hiện hành. Đợi terminal báo `Application startup complete`, rồi kiểm tra tại `http://127.0.0.1:8080/`. Phản hồi cần có `"model_loaded": true`.

Tài liệu OpenAPI tự sinh có thể xem tại `http://127.0.0.1:8080/docs` khi backend đang chạy.

## Chạy ứng dụng Flutter

Ở terminal khác tại thư mục gốc:

```powershell
flutter pub get
flutter run -d edge
```

Lệnh này phù hợp khi mở Flutter Web trên cùng máy đang chạy backend, vì địa chỉ mặc định của Web là `http://127.0.0.1:8080`.

### Chạy frontend và backend với một lệnh

Sau khi đã tạo `backend_ai/.venv` và cài requirements một lần, có thể chạy:

```powershell
.\dev.ps1
```

Script kiểm tra backend hiện có; nếu chưa báo model sẵn sàng, script khởi chạy backend, chờ tối đa 120 giây rồi mở Flutter Web bằng Edge. Nếu script khởi tạo backend, tiến trình đó sẽ dừng khi Flutter kết thúc. Nếu PowerShell chặn script, có thể cho phép thực thi trong cửa sổ hiện tại:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\dev.ps1
```

## Kết nối frontend với backend

Flutter dùng compile-time define `API_BASE_URL`, đọc trong `lib/money_identifier_app.dart`. Không thêm dấu `/` cuối địa chỉ là cách viết khuyến nghị; ứng dụng cũng loại bỏ dấu `/` cuối trước khi ghép endpoint.

| Môi trường frontend | Địa chỉ mặc định | Ghi chú |
| --- | --- | --- |
| Flutter Web | `http://127.0.0.1:8080` | Dùng khi trình duyệt chạy trên chính máy backend. |
| Android Emulator | `http://10.0.2.2:8080` | `10.0.2.2` trỏ từ emulator Android về máy phát triển. |
| Windows/macOS/Linux | `http://127.0.0.1:8080` | Dùng khi frontend và backend ở cùng máy. |
| Điện thoại thật hoặc máy khác | Cần truyền địa chỉ LAN của máy backend | Hai máy cần liên lạc được qua mạng; backend đang bind `0.0.0.0:8080`. |

Ví dụ chạy Flutter Web/thiết bị khác với backend ở địa chỉ LAN `192.168.1.20`:

```powershell
flutter run -d edge --dart-define=API_BASE_URL=http://192.168.1.20:8080
```

Thay địa chỉ ví dụ bằng IPv4 thực của máy chạy backend. Để dùng thiết bị thật, cần cho phép kết nối qua firewall và bảo đảm thiết bị truy cập được cổng `8080` của máy backend.

Backend bật CORS cho mọi origin để thuận tiện phát triển. HTTP không mã hóa và cấu hình này không phù hợp để đưa thẳng lên môi trường công khai; khi triển khai cần dùng HTTPS và giới hạn CORS theo origin thực tế.

## API

### `GET /` — kiểm tra trạng thái

Kiểm tra API và trạng thái nạp model. Flutter tự gọi endpoint này lúc mở ứng dụng.

Ví dụ phản hồi:

```json
{
  "status": "ok",
  "model_loaded": true,
  "model": "best.onnx"
}
```

`model_loaded: false` nghĩa là model chưa sẵn sàng; trong cấu hình hiện tại, backend sẽ báo lỗi nếu file model không tồn tại khi khởi động.

### `POST /predict` — phát hiện và quy đổi tiền

- Content-Type: `multipart/form-data`
- Thành công: HTTP `200`, nội dung JSON.
- Trường bắt buộc: `file` — file ảnh.
- Các trường form tùy chọn:

| Tên | Kiểu | Mặc định | Ý nghĩa |
| --- | --- | --- | --- |
| `from_currency` | chuỗi | `VND` | Tiền tệ người dùng chọn làm nguồn; được dùng để so sánh với loại tiền model phát hiện và tạo thông báo `currency_match`. Loại tiền thực tế đem quy đổi được suy ra từ nhãn model. |
| `to_currency` | chuỗi | `USD` | Loại tiền đích cho tổng quy đổi. |
| `confidence_threshold` | số thực | `0.25` | Ngưỡng confidence của detector; backend giới hạn giá trị trong khoảng `0.01` đến `1.0`. |
| `overlap_threshold` | số thực | `0.45` | Ngưỡng IoU/NMS của YOLO; backend giới hạn giá trị trong khoảng `0.01` đến `1.0`. |

Ví dụ gọi API bằng `curl`:

```bash
curl -X POST "http://127.0.0.1:8080/predict" \
  -F "file=@banknote.jpg" \
  -F "from_currency=VND" \
  -F "to_currency=USD" \
  -F "confidence_threshold=0.25" \
  -F "overlap_threshold=0.45"
```

Ví dụ gửi bằng Python:

```python
import requests

with open("banknote.jpg", "rb") as image:
    response = requests.post(
        "http://127.0.0.1:8080/predict",
        files={"file": ("banknote.jpg", image, "image/jpeg")},
        data={
            "from_currency": "VND",
            "to_currency": "USD",
            "confidence_threshold": "0.25",
            "overlap_threshold": "0.45",
        },
        timeout=90,
    )

response.raise_for_status()
print(response.json())
```

Các mã tiền hiện được hỗ trợ: `VND`, `USD`, `EUR`, `CNY`, `JPY`, `THB`, `TRY`, `KHR`, `KRW`, `INR`. Nhãn model mới như `cbr_1k`, `ndt_20`, `eur_10`, `yen_1k`, `try_50` được ánh xạ lần lượt sang `KHR`, `CNY`, `EUR`, `JPY`, `TRY`; hậu tố `k` và `m` trong mệnh giá nhân lần lượt 1.000 và 1.000.000.

## Định dạng phản hồi

Khi phát hiện được các nhãn hợp lệ, phản hồi có dạng khái quát:

```json
{
  "detected_label": "50.000 VND",
  "converted_amount": "1,93 USD",
  "exchange_rate": "1.000 VND = 0,04 USD",
  "confidence": 0.91,
  "count": 1,
  "detected_currency": "VND",
  "selected_source_currency": "VND",
  "currency_match": true,
  "currency_totals": {"VND": 50000},
  "total_detected": 50000,
  "detections": [
    {
      "label": "vnd_50k",
      "currency": "VND",
      "value": 50000,
      "confidence": 0.91,
      "box": [0.12, 0.18, 0.81, 0.76]
    }
  ],
  "image_width": 1200,
  "image_height": 800,
  "confidence_threshold": 0.25,
  "overlap_threshold": 0.45,
  "security_check": "..."
}
```

Các số trong ví dụ chỉ để minh họa cấu trúc; kết quả thực tế tùy ảnh và model. `box` là tọa độ chuẩn hóa theo thứ tự `[x1, y1, x2, y2]`, mỗi tọa độ nằm trong khoảng tương đối so với chiều rộng/cao ảnh. `confidence` ở cấp kết quả là trung bình confidence của các detection hợp lệ. `count` là số tờ phát hiện được. `detected_currency` là mã tiền nếu chỉ có một loại, hoặc `MIXED` nếu ảnh có nhiều loại. `currency_totals` luôn tổng hợp theo mã tiền; `total_detected` chỉ có giá trị khi chỉ phát hiện một loại.

Nếu không tìm thấy tờ tiền, backend vẫn trả HTTP `200` cùng các trường `detected_label`, `converted_amount: "0"`, `count: 0`, `total_detected: 0`, và lý do trong `security_check`; trường `detections` không được thêm vào nhánh này. Nếu phát hiện đối tượng nhưng không phân tích được nhãn mệnh giá, phản hồi cũng có cấu trúc không phát hiện và mô tả trường hợp đó.

Lỗi đầu vào trả HTTP 400 (ảnh rỗng hoặc không giải mã được); model chưa nạp trả HTTP 503. FastAPI trả phần giải thích trong trường `detail`. Flutter hiển thị mã HTTP và `detail` nếu nhận lỗi.

## Cách tính kết quả

1. Model trả các bounding box, class ID và confidence. Backend tra class ID qua tên nhãn model.
2. Tiền tố nhãn xác định tiền tệ; phần số sau dấu `_` xác định mệnh giá. Nhãn không khớp một trong năm loại tiền hoặc không có giá trị số sẽ bị bỏ qua.
3. Giá trị mệnh giá của từng detection được cộng vào tổng của đồng tiền tương ứng. Ảnh có nhiều loại tiền sẽ được cộng riêng từng loại.
4. Backend dùng tỷ giá mỗi đơn vị tiền so với VND trong `VND_PER_UNIT`, đổi từng tổng sang VND rồi quy đổi sang tiền đích. Tỷ giá chéo được tính từ hai tỷ giá so với VND.
5. VND/KRW được định dạng không có chữ số thập phân; các loại khác hiển thị hai chữ số thập phân. Làm tròn dùng `ROUND_HALF_UP`.

Bảng tỷ giá tham khảo từ `Bang_Ty_Gia_Ngoai_Te_Full.xlsx` được mã hóa cố định trong `backend_ai/main.py`; đây không phải nguồn tỷ giá trực tiếp và không tự cập nhật. Mỗi giá trị là số VND cho một đơn vị ngoại tệ:

| Mã tiền tệ | USD | EUR | CNY | JPY | THB | TRY | INR | KRW | KHR | VND |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 đơn vị đổi ra VND | 25.500 | 28.500 | 3.800 | 160 | 750 | 515 | 275 | 18,5 | 6,3 | 1 |

Ví dụ: 50.000 VND đổi sang USD theo bảng hiện tại là `50.000 ÷ 25.500 ≈ 1,96 USD`.

## Lỗi thường gặp

| Hiện tượng | Nguyên nhân/khắc phục |
| --- | --- |
| Backend không khởi động, báo thiếu model | Đặt đúng file `best.onnx` tại `backend_ai/best.onnx`. |
| `model_loaded` không phải `true` | Chờ model nạp xong; xem log terminal backend để biết lỗi khởi động. |
| Flutter không kết nối được | Mở `GET /` trên máy backend; kiểm tra cổng 8080, địa chỉ `API_BASE_URL`, mạng và firewall. Trên Android Emulator dùng `10.0.2.2`, không dùng `127.0.0.1` của emulator. |
| CORS khi chạy Web | Backend hiện cho phép mọi origin. Nếu thay đổi cấu hình, cần cho phép origin đang phục vụ Flutter Web. |
| Camera không mở | Cấp quyền camera cho hệ điều hành/trình duyệt; kiểm tra thiết bị có camera. |
| Không nhận diện được tiền | Chụp ảnh đủ sáng, lấy nét, tránh che khuất và đặt tờ tiền rõ trong khung; kết quả còn phụ thuộc dữ liệu huấn luyện và các ngưỡng detector. |
| Báo cặp tiền chưa hỗ trợ | Kiểm tra mã `to_currency` và bảng `VND_PER_UNIT`; API hiện hỗ trợ mười mã tiền được liệt kê ở trên. |

## Giới hạn và lưu ý

- Model chỉ phân loại theo các lớp có trong `best.onnx`; các mã tiền nêu trên phản ánh logic ánh xạ hiện tại, không đảm bảo model có đủ lớp hoặc nhận diện chính xác mọi mẫu tiền.
- `from_currency` là lựa chọn của giao diện để so sánh/hiển thị cảnh báo. Backend quy đổi dựa trên loại tiền model nhận diện; nếu khác lựa chọn, phản hồi đặt `currency_match` thành `false` và ghi chú trong `security_check`.
- `security_check` chỉ báo loại tiền model phát hiện và lựa chọn của người dùng. Ứng dụng không xác minh tiền thật/giả.
- Bảng tỷ giá cố định nên chỉ phục vụ mục đích minh họa/tham khảo trong phạm vi ứng dụng.
- Backend cho phép CORS rộng và dùng HTTP local để phát triển. Khi triển khai, cần cấu hình HTTPS, CORS theo domain, giới hạn truy cập mạng và cách quản lý model phù hợp môi trường chạy.

## Demo trên điện thoại cùng Wi-Fi

Demo này chạy Flutter Web trên laptop và mở giao diện bằng Chrome trên điện thoại. Laptop chạy backend nhận diện, nên cần bật và giữ terminal demo chạy trong suốt buổi demo. Hai thiết bị phải cùng mạng Wi-Fi.

1. Đảm bảo đã cài đặt dependencies Flutter/Python, và có `backend_ai/best.onnx`.
2. Mở PowerShell tại thư mục gốc dự án và chạy:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\run-mobile-demo.ps1
   ```

3. Lần đầu, nếu Windows Firewall hỏi quyền, cho phép Python/Flutter trên mạng Private.
4. Script in địa chỉ kiểu `http://192.168.x.x:5000`. Mở địa chỉ đó trong Chrome trên điện thoại. Nếu không tải được, kiểm tra hai thiết bị cùng Wi-Fi, mạng không bật client isolation, và firewall cho phép cổng TCP `5000` (giao diện) và `8080` (API).
5. Chọn ảnh từ thư viện hoặc dùng nút chụp ảnh. Trong Chrome, thao tác chụp có thể mở camera theo giao diện chọn ảnh của Android.
6. Trên Chrome Android, mở menu `⋮` rồi chọn `Thêm vào màn hình chính` (hoặc `Cài đặt ứng dụng` nếu Chrome hiện mục đó). Sau đó mở biểu tượng vừa thêm như ứng dụng.
7. Giữ laptop bật, không sleep, và giữ PowerShell/script chạy. Nhấn `Ctrl+C` để dừng demo.

Nếu PowerShell chặn script, lệnh `Set-ExecutionPolicy -Scope Process Bypass` chỉ có hiệu lực trong cửa sổ hiện tại. Script tự dò IPv4 LAN và khởi động backend nếu chưa có backend sẵn sàng; khi dừng script, backend do script tạo cũng được dừng. Kết quả nhận diện vẫn cần backend báo `model_loaded: true` tại URL cổng `8080`.

Đây là demo HTTP trong mạng nội bộ. Không dùng khi laptop và điện thoại đang ở mạng công cộng không tin cậy. Để truy cập qua Internet hoặc cài PWA chuẩn cần đưa frontend/API lên host có HTTPS; URL LAN của laptop không hoạt động khi điện thoại ở ngoài Wi-Fi nhà.

# Money Identifier AI

Ứng dụng Flutter Android chụp/chọn ảnh tiền giấy và gửi ảnh tới backend FastAPI chạy trên laptop. Backend dùng model `backend_ai/best.onnx` để nhận diện. APK không chứa backend hoặc model.

## Chạy toàn bộ luồng

Sau khi cài backend một lần theo bước dưới đây, chạy cả backend và web bằng một lệnh:

```powershell
.\run-project.ps1
```

Lệnh này tự mở backend nếu chưa chạy, đợi model tải xong rồi mở Flutter Web trên Edge. Khi thoát Flutter bằng `q` hoặc dừng script, backend do script mở cũng sẽ dừng.

### 1. Cài backend trên laptop (làm một lần)

Mở PowerShell tại thư mục dự án:

```powershell
cd backend_ai
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
cd ..
```

### 2. Kết nối điện thoại và laptop cùng mạng

Điện thoại Android và laptop phải ở cùng Wi-Fi hoặc cùng mạng hotspot. Trên laptop, chạy `ipconfig`, tìm `IPv4 Address` của adapter đang kết nối mạng. Ví dụ `192.168.1.20`.

Nếu dùng hotspot điện thoại để cấp mạng cho laptop, lấy IPv4 của adapter Wi-Fi trên laptop. Điện thoại có thể truy cập laptop qua mạng hotspot nếu hotspot và Windows Firewall cho phép kết nối giữa các thiết bị.

### 3. Khởi động backend

Tại thư mục dự án, chạy:

```powershell
.\run-mobile-backend.ps1
```

Giữ cửa sổ PowerShell này mở. Khi thấy backend đã tải model, thử mở `http://IP-LAPTOP:8080/` trên điện thoại. Thay `IP-LAPTOP` bằng địa chỉ IPv4 ở bước trước. Phản hồi cần có `"model_loaded": true`.

Nếu điện thoại không truy cập được, cho phép Python hoặc TCP cổng `8080` qua Windows Firewall trên mạng Private, rồi thử lại. Không dùng `localhost` hoặc `127.0.0.1` trong điện thoại: các địa chỉ đó trỏ về chính điện thoại.

### 4. Build APK trỏ tới laptop

Tại thư mục dự án, chạy:

```powershell
.\build-android-apk.ps1 -BackendUrl "http://IP-LAPTOP:8080"
```

APK được tạo tại:

```text
build\app\outputs\flutter-apk\app-release.apk
```

Chép APK sang điện thoại, cài đặt, cấp quyền camera nếu được hỏi, rồi dùng ứng dụng. Nếu IP laptop đổi, build lại APK với IP mới.

## Android Emulator

Khi chạy trên Android Emulator cùng laptop, địa chỉ backend thường là `http://10.0.2.2:8080`. Khi đó có thể build bằng:

```powershell
.\build-android-apk.ps1 -BackendUrl "http://10.0.2.2:8080"
```

## Cấu trúc chính

- `lib/`: ứng dụng Flutter Android.
- `android/`: cấu hình Android và APK.
- `backend_ai/main.py`: API FastAPI.
- `backend_ai/best.onnx`: model nhận diện.
- `run-mobile-backend.ps1`: khởi động backend trên laptop, lắng nghe trên mạng nội bộ.
- `build-android-apk.ps1`: build APK với địa chỉ backend được truyền vào.

## Chạy giao diện Web trên laptop

Có thể dùng lệnh tổng hợp `.\run-project.ps1` ở trên. Nếu muốn chạy từng phần riêng, khởi động backend bằng `.\run-mobile-backend.ps1`, rồi mở PowerShell khác và chạy:

```powershell
.\run-local-web.ps1
```

Flutter Web mở trên Edge và gọi backend ở `http://127.0.0.1:8080`. Để mở web trên điện thoại cùng mạng, chạy Flutter Web Server thay vì Edge:

```powershell
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 5000 --dart-define=API_BASE_URL=http://IP-LAPTOP:8080
```

Trên điện thoại, mở `http://IP-LAPTOP:5000`. Thay `IP-LAPTOP` bằng IPv4 của laptop. Windows Firewall cần cho phép cổng `5000` (web) và `8080` (API) trên mạng Private. Hotspot có thể chặn kết nối giữa các thiết bị; hãy thử mở endpoint backend trên điện thoại trước.

Ứng dụng Web và APK dùng chung backend trên laptop. Backend phải chạy, và thiết bị Android phải kết nối được tới laptop qua Wi-Fi/hotspot. Dự án không cần domain hoặc máy chủ thuê.

# Cài ứng dụng Android

Dự án đã có ứng dụng Flutter native cho Android và iOS. Hướng dẫn này tạo APK Android để cài trực tiếp. Ứng dụng gửi ảnh đến FastAPI; model `backend_ai/best.onnx` vẫn chạy trên máy tính hoặc máy chủ có backend.

## Tạo APK

Trên máy tính đã cài Flutter SDK, mở PowerShell tại thư mục dự án:

```powershell
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=http://DIA-CHI-IP-MAY-TINH:8080
```

Thay `DIA-CHI-IP-MAY-TINH` bằng địa chỉ IPv4 nội bộ của máy đang chạy backend, ví dụ `192.168.1.20`. APK sẽ nằm tại:

```text
build\app\outputs\flutter-apk\app-release.apk
```

Nếu muốn cài lên Android Emulator trên chính máy build, dùng URL `http://10.0.2.2:8080`. Với điện thoại thật, không dùng `localhost` hoặc `127.0.0.1`: các địa chỉ đó trỏ về điện thoại.

## Cài và chạy

1. Trên máy tính, khởi động backend từ thư mục gốc:

   ```powershell
   cd backend_ai
   .\.venv\Scripts\Activate.ps1
   python -m uvicorn main:app --host 0.0.0.0 --port 8080
   ```

   Nếu chưa cài môi trường backend, xem phần cài backend trong `README.md`. Đảm bảo `backend_ai/best.onnx` có mặt và backend báo đã nạp model.
2. Máy tính và điện thoại cùng kết nối Wi-Fi. Trên điện thoại, mở `http://DIA-CHI-IP-MAY-TINH:8080/` trong trình duyệt. Phản hồi cần có `"model_loaded": true`. Nếu không mở được, cho phép TCP cổng `8080` qua Windows Firewall trên mạng Private.
3. Chép `app-release.apk` sang điện thoại (USB, Drive hoặc cách chia sẻ file khác), mở file và cho phép cài ứng dụng từ nguồn này nếu Android hỏi.
4. Mở **Money Identifier AI**, cấp quyền camera khi được hỏi, rồi chụp/chọn ảnh để nhận diện.

Giữ máy chạy backend bật và cùng mạng với điện thoại khi dùng. APK chỉ chứa ứng dụng; backend và model chưa được đóng gói vào APK. Để dùng khi không cùng Wi-Fi, cần triển khai backend lên máy chủ có HTTPS rồi build lại với URL HTTPS đó.

## Build để cài lên điện thoại khác

Mỗi URL backend cần được ghi vào APK lúc build. Khi đổi IP/backend, build lại với `--dart-define=API_BASE_URL=...` rồi cài APK mới. Để cài trực tiếp qua USB với Android USB debugging bật, có thể chạy:

```powershell
flutter install --release --dart-define=API_BASE_URL=http://DIA-CHI-IP-MAY-TINH:8080
```

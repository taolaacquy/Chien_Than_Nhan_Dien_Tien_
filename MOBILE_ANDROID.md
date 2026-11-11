# Android APK sử dụng backend trên laptop

APK gọi backend qua địa chỉ IPv4 nội bộ của laptop. Điện thoại và laptop cần ở cùng mạng Wi-Fi/hotspot; backend phải đang chạy.

1. Trên laptop, chạy `ipconfig` và lấy `IPv4 Address` của adapter đang kết nối mạng.
2. Tại thư mục dự án, khởi động backend:

   ```powershell
   .\run-mobile-backend.ps1
   ```

3. Tạo APK với địa chỉ laptop:

   ```powershell
   .\build-android-apk.ps1 -BackendUrl "http://IP-LAPTOP:8080"
   ```

4. Cài `build\app\outputs\flutter-apk\app-release.apk` lên điện thoại. Giữ laptop, backend và mạng kết nối hoạt động khi dùng ứng dụng.

Mở `http://IP-LAPTOP:8080/` trên điện thoại để kiểm tra API trước. Cần thấy `"model_loaded": true`. Nếu không mở được, kiểm tra hai thiết bị cùng mạng và cho phép TCP cổng `8080` qua Windows Firewall trên mạng Private.

Với Android Emulator, dùng `http://10.0.2.2:8080` thay cho IP laptop.

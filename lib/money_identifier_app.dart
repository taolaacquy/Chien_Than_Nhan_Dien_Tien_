import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class MoneyIdentifierApp extends StatefulWidget {
  const MoneyIdentifierApp({super.key, this.width, this.height});

  final double? width;
  final double? height;

  @override
  State<MoneyIdentifierApp> createState() => _MoneyIdentifierAppState();
}

class _DetectionOverlay extends CustomPainter {
  _DetectionOverlay(
    dynamic detections, {
    this.fit = BoxFit.contain,
    this.imageWidth = 1,
    this.imageHeight = 1,
  }) : detections = detections is List ? detections : const [];

  final List detections;
  final BoxFit fit;
  final int imageWidth;
  final int imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final boxes = detections.whereType<Map>().toList();
    if (boxes.isEmpty) return;
    final source = Size(imageWidth.toDouble(), imageHeight.toDouble());
    final fitted = applyBoxFit(fit, source, size);
    final rect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    for (final detection in boxes) {
      final coords = detection['box'];
      if (coords is! List || coords.length != 4) continue;
      final x1 = (coords[0] as num).toDouble();
      final y1 = (coords[1] as num).toDouble();
      final x2 = (coords[2] as num).toDouble();
      final y2 = (coords[3] as num).toDouble();
      final box = Rect.fromLTRB(
        rect.left + x1 * rect.width,
        rect.top + y1 * rect.height,
        rect.left + x2 * rect.width,
        rect.top + y2 * rect.height,
      );
      canvas.drawRect(
        box,
        Paint()
          ..color = _MoneyIdentifierAppState._cyan
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      final label =
          '${detection['label'] ?? ''} ${(100 * ((detection['confidence'] as num?)?.toDouble() ?? 0)).round()}%';
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.8);
      final labelRect = Rect.fromLTWH(
        box.left,
        (box.top - 22).clamp(0, size.height),
        painter.width + 10,
        20,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(5)),
        Paint()..color = _MoneyIdentifierAppState._cyan,
      );
      painter.paint(canvas, Offset(labelRect.left + 5, labelRect.top + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionOverlay oldDelegate) =>
      oldDelegate.detections != detections || oldDelegate.fit != fit;
}

class _MoneyIdentifierAppState extends State<MoneyIdentifierApp>
    with WidgetsBindingObserver {
  static const _background = Color(0xFF080B14);
  static const _panel = Color(0xFF111827);
  static const _cyan = Color(0xFF4DE4E8);
  static const _muted = Color(0xFF93A4B8);
  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static const _currencies = <Map<String, String>>[
    {'code': 'VND', 'name': 'Việt Nam', 'flag': '🇻🇳'},
    {'code': 'USD', 'name': 'Hoa Kỳ', 'flag': '🇺🇸'},
    {'code': 'EUR', 'name': 'Khu vực Euro', 'flag': '🇪🇺'},
    {'code': 'CNY', 'name': 'Trung Quốc', 'flag': '🇨🇳'},
    {'code': 'JPY', 'name': 'Nhật Bản', 'flag': '🇯🇵'},
    {'code': 'THB', 'name': 'Thái Lan', 'flag': '🇹🇭'},
    {'code': 'TRY', 'name': 'Thổ Nhĩ Kỳ', 'flag': '🇹🇷'},
    {'code': 'KHR', 'name': 'Campuchia', 'flag': '🇰🇭'},
    {'code': 'KRW', 'name': 'Hàn Quốc', 'flag': '🇰🇷'},
    {'code': 'INR', 'name': 'Ấn Độ', 'flag': '🇮🇳'},
  ];

  final _picker = ImagePicker();
  CameraController? _cameraController;
  bool _cameraInitializing = false;
  bool _resumeCameraOnForeground = false;
  late Map<String, String> _homeCurrency;
  late Map<String, String> _sourceCurrency;
  Uint8List? _imageBytes;
  Map<String, dynamic>? _result;
  String? _error;
  bool _loading = false;
  double _confidenceThreshold = 0.25;
  double _overlapThreshold = 0.45;
  bool? _backendOnline;
  int _page = 0;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_cameraController != null) {
        _resumeCameraOnForeground = true;
        _releaseCamera();
      }
    } else if (state == AppLifecycleState.resumed &&
        _resumeCameraOnForeground &&
        _page == 1) {
      _resumeCameraOnForeground = false;
      _initializeCamera();
    }
  }

  Future<void> _openScanner() async {
    await _releaseCamera();
    if (!mounted) return;
    setState(() {
      _page = 1;
      _error = null;
      _result = null;
      _imageBytes = null;
    });
    await _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (_cameraInitializing) return;
    setState(() {
      _cameraInitializing = true;
      _error = null;
    });
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('Kh?ng t?m th?y camera tr?n thi?t b?.');
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted || _page != 1) {
        await controller.dispose();
        if (mounted) setState(() => _cameraInitializing = false);
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraInitializing = false;
      });
    } catch (error) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _cameraInitializing = false;
        if (_page == 1) {
          _error =
              'Kh?ng m? ???c camera. H?y c?p quy?n camera r?i th? l?i.\n$error';
        }
      });
    }
  }

  Future<void> _releaseCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    await controller?.dispose();
  }

  Future<void> _captureCamera() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final image = await controller.takePicture();
      final bytes = await image.readAsBytes();
      await _releaseCamera();
      if (!mounted) return;
      setState(() => _imageBytes = bytes);
      await _recognize(bytes, image.name);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Kh?ng ch?p ???c ?nh t? camera.\n$error';
      });
    }
  }

  void _goHome() {
    _releaseCamera();
    setState(() => _page = 0);
  }

  String get _baseUrl {
    final configured = _apiBaseUrl.trim();
    if (configured.isNotEmpty) {
      return configured.replaceFirst(RegExp(r'/+$'), '');
    }
    if (kIsWeb) return 'http://127.0.0.1:8080';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://127.0.0.1:8080';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _homeCurrency = _currencies[1];
    _sourceCurrency = _currencies[0];
    _checkBackend();
  }

  Future<void> _checkBackend() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/'))
          .timeout(const Duration(seconds: 4));
      final body = jsonDecode(response.body);
      if (!mounted) return;
      setState(() {
        _backendOnline =
            response.statusCode == 200 &&
            body is Map<String, dynamic> &&
            body['model_loaded'] == true;
      });
    } catch (_) {
      if (mounted) setState(() => _backendOnline = false);
    }
  }

  Future<void> _chooseImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) await _releaseCamera();
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _error = null;
        _result = null;
        _loading = true;
        _page = 1;
      });
      await _recognize(bytes, picked.name);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Kh?ng th? m? ?nh ?? ch?n.\n$error';
        _page = 1;
      });
    }
  }

  Future<void> _recognize(Uint8List bytes, String filename) async {
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse('$_baseUrl/predict'))
            ..fields['from_currency'] = _sourceCurrency['code']!
            ..fields['to_currency'] = _homeCurrency['code']!
            ..fields['confidence_threshold'] = _confidenceThreshold
                .toStringAsFixed(2)
            ..fields['overlap_threshold'] = _overlapThreshold.toStringAsFixed(2)
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                bytes,
                filename: filename.isEmpty ? 'banknote.jpg' : filename,
              ),
            );

      final streamed = await request.send().timeout(
        const Duration(seconds: 90),
      );
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        var message = response.body;
        try {
          final body = jsonDecode(response.body);
          if (body is Map<String, dynamic>) {
            message = '${body['detail'] ?? response.body}';
          }
        } catch (_) {}
        throw Exception('HTTP ${response.statusCode}: $message');
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw const FormatException('Backend tr? v? d? li?u kh?ng h?p l?.');
      }
      if (!mounted) return;
      setState(() {
        _result = body;
        _loading = false;
        _backendOnline = true;
        _page = 2;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _backendOnline = false;
        _error = 'Kh?ng k?t n?i ???c backend t?i $_baseUrl.\n$error';
      });
    }
  }

  void _swapCurrencies() {
    setState(() {
      final previousHome = _homeCurrency;
      _homeCurrency = _sourceCurrency;
      _sourceCurrency = previousHome;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.width == null
                  ? 760
                  : widget.width!.clamp(0, 760).toDouble(),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: _page == 0
                  ? _homePage()
                  : _page == 1
                  ? _scannerPage()
                  : _page == 2
                  ? _resultPage()
                  : _helpPage(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _homePage() {
    return SingleChildScrollView(
      key: const ValueKey('home'),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _brandMark(size: 42),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MONEY SENSE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'AI currency companion',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _backendBadge(),
              IconButton(
                tooltip: 'Hướng dẫn',
                onPressed: () => setState(() => _page = 3),
                icon: const Icon(Icons.help_outline_rounded, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _heroCard(),
          const SizedBox(height: 22),
          _sectionLabel(
            'QUY ĐỔI TIỀN TỆ',
            'Chọn tiền bạn có và tiền muốn nhận',
          ),
          const SizedBox(height: 12),
          _currencyPanel(),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _primaryButton(
                  label: 'Mở camera',
                  icon: Icons.camera_alt_rounded,
                  onPressed: _openScanner,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _secondaryButton(
                  label: 'Thư viện ảnh',
                  icon: Icons.photo_library_outlined,
                  onPressed: () => _chooseImage(ImageSource.gallery),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Center(
            child: Text(
              'Chụp hoặc tải ảnh tiền giấy để AI nhận diện mệnh giá',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel('HƯỚNG DẪN NHANH', 'Ba bước để có kết quả'),
          const SizedBox(height: 12),
          Row(
            children: [
              _stepCard(
                '01',
                Icons.photo_camera_back_outlined,
                'Chụp hoặc chọn ảnh',
              ),
              const SizedBox(width: 10),
              _stepCard('02', Icons.auto_awesome, 'AI nhận diện'),
              const SizedBox(width: 10),
              _stepCard('03', Icons.currency_exchange, 'Xem quy đổi'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _helpPage() {
    return SingleChildScrollView(
      key: const ValueKey('help'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeader('Hướng dẫn sử dụng', 'Nhận diện và quy đổi tiền giấy'),
          const SizedBox(height: 18),
          _detailCard(
            icon: Icons.tune_rounded,
            title: '1. Chọn tiền cần quy đổi',
            detail: 'Chọn loại tiền của tờ tiền trong mục “Tiền bạn có”, sau đó chọn đồng tiền muốn nhận.',
          ),
          const SizedBox(height: 10),
          _detailCard(
            icon: Icons.camera_alt_outlined,
            title: '2. Chụp bằng camera',
            detail: 'Nhấn “Mở camera”, đặt tờ tiền trong khung và giữ máy ổn định để ảnh rõ nét.',
          ),
          const SizedBox(height: 10),
          _detailCard(
            icon: Icons.photo_library_outlined,
            title: 'Hoặc tải từ thư viện',
            detail: 'Nhấn “Thư viện ảnh” để chọn ảnh có sẵn. Có thể nhận diện nhiều tờ tiền trong một ảnh.',
          ),
          const SizedBox(height: 10),
          _detailCard(
            icon: Icons.auto_awesome,
            title: '3. Xem kết quả AI',
            detail: 'Ứng dụng hiển thị mệnh giá, số tờ, độ tin cậy và tổng tiền sau quy đổi.',
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF102A33),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _cyan.withValues(alpha: 0.22)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TỶ GIÁ ĐANG DÙNG',
                  style: TextStyle(
                    color: _cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Theo bảng tỷ giá được cung cấp. Ví dụ: 50.000 VND ≈ 1,93 USD.',
                  style: TextStyle(color: Colors.white, height: 1.45),
                ),
                SizedBox(height: 6),
                Text(
                  'Tỷ giá là dữ liệu cố định trong ứng dụng, không tự cập nhật theo thị trường.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _detailCard(
            icon: Icons.info_outline_rounded,
            title: 'Lưu ý về nhận diện',
            detail: 'Model hỗ trợ VND, USD, KRW, THB và INR. Kết quả AI chỉ là nhận diện hình ảnh, không xác thực tiền thật hay tiền giả.',
          ),
          const SizedBox(height: 20),
          _primaryButton(
            label: 'Bắt đầu quét tiền',
            icon: Icons.document_scanner_rounded,
            onPressed: _openScanner,
          ),
        ],
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF172943), Color(0xFF17172F), Color(0xFF111827)],
        ),
        border: Border.all(color: _cyan.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: _cyan.withValues(alpha: 0.08),
            blurRadius: 30,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            top: 2,
            child: Icon(
              Icons.blur_on_rounded,
              size: 112,
              color: _cyan.withValues(alpha: 0.09),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _cyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: _cyan),
                    SizedBox(width: 6),
                    Text(
                      'AI POWERED',
                      style: TextStyle(
                        color: _cyan,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Tiền tệ trong\ntầm mắt.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Nhận diện tiền giấy nhanh chóng và xem giá trị quy đổi ngay.',
                style: TextStyle(
                  color: Color(0xFFB7C5D8),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _currencyPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          _currencyDropdown(
            label: 'TIỀN BẠN CÓ',
            value: _sourceCurrency,
            onChanged: (value) {
              if (value != null) setState(() => _sourceCurrency = value);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Divider(color: Colors.white.withValues(alpha: 0.08)),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: _swapCurrencies,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF202B3C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _cyan.withValues(alpha: 0.25)),
                    ),
                    child: const Icon(
                      Icons.swap_vert_rounded,
                      color: _cyan,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Divider(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ],
            ),
          ),
          _currencyDropdown(
            label: 'ĐỔI SANG',
            value: _homeCurrency,
            onChanged: (value) {
              if (value != null) setState(() => _homeCurrency = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _currencyDropdown({
    required String label,
    required Map<String, String> value,
    required ValueChanged<Map<String, String>?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _muted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 7),
        DropdownButtonFormField<Map<String, String>>(
          initialValue: value,
          dropdownColor: const Color(0xFF1B2638),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _muted),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0C1320),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 5,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: _cyan),
            ),
          ),
          items: _currencies.map((currency) {
            return DropdownMenuItem(
              value: currency,
              child: Text(
                '${currency['flag']}   ${currency['name']}  ·  ${currency['code']}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _scannerPage() {
    return SingleChildScrollView(
      key: const ValueKey('scanner'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeader('Quét tiền', 'Đặt tờ tiền trong khung hình'),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            height: 310,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _cyan.withValues(alpha: 0.55),
                width: 1.2,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                if (_imageBytes != null)
                  Image.memory(_imageBytes!, fit: BoxFit.contain)
                else if (_cameraController?.value.isInitialized == true)
                  CameraPreview(_cameraController!)
                else
                  const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        color: Color(0xFF63748B),
                        size: 56,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Đang mở camera...',
                        style: TextStyle(color: _muted),
                      ),
                    ],
                  ),
                if (_imageBytes != null && _result != null)
                  CustomPaint(
                    painter: _DetectionOverlay(
                      _result!['detections'],
                      imageWidth: _result!['image_width'] ?? 1,
                      imageHeight: _result!['image_height'] ?? 1,
                    ),
                  ),
                Positioned(
                  right: 7,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 96,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xE6101828),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.tune_rounded, color: _cyan, size: 17),
                        Text(
                          'Tin cậy ${(100 * _confidenceThreshold).round()}%',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                        ),
                        Slider(
                          value: _confidenceThreshold,
                          min: 0.05,
                          max: 0.95,
                          onChanged: _loading
                              ? null
                              : (v) => setState(() => _confidenceThreshold = v),
                        ),
                        Text(
                          'Chồng lấp ${(100 * _overlapThreshold).round()}%',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                        ),
                        Slider(
                          value: _overlapThreshold,
                          min: 0.05,
                          max: 0.95,
                          onChanged: _loading
                              ? null
                              : (v) => setState(() => _overlapThreshold = v),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_loading)
                  Container(
                    color: Colors.black.withValues(alpha: 0.62),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 38,
                          height: 38,
                          child: CircularProgressIndicator(
                            color: _cyan,
                            strokeWidth: 3,
                          ),
                        ),
                        SizedBox(height: 14),
                        Text(
                          'AI đang phân tích ảnh...',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _errorPanel(_error!),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _secondaryButton(
                  label: 'Thư viện ảnh',
                  icon: Icons.photo_library_outlined,
                  onPressed: (_loading || _cameraInitializing)
                      ? null
                      : () => _chooseImage(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _primaryButton(
                  label: _cameraController == null
                      ? 'Mở lại camera'
                      : 'Chụp ảnh',
                  icon: Icons.camera_alt_rounded,
                  onPressed: (_loading || _cameraInitializing)
                      ? null
                      : _cameraController == null
                      ? _openScanner
                      : _captureCamera,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _loading ? null : _goHome,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Quay lại'),
              style: TextButton.styleFrom(foregroundColor: _muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultPage() {
    final result = _result ?? const <String, dynamic>{};
    final count = result['count'] ?? 0;
    final detected = '${result['detected_label'] ?? 'Chưa nhận diện'}';
    final converted = '${result['converted_amount'] ?? '—'}';
    final exchangeRate = '${result['exchange_rate'] ?? ''}';
    final currencyTotals = result['currency_totals'];
    final detectedCountries = currencyTotals is Map
        ? currencyTotals.keys
              .map((code) {
                final match = _currencies.where(
                  (currency) => currency['code'] == '$code',
                );
                return match.isEmpty
                    ? '$code'
                    : '${match.first['name']} ($code)';
              })
              .join(', ')
        : '${result['detected_currency'] ?? 'Ch?a x?c ??nh'}';
    final confidence = result['confidence'];
    final confidencePercent = confidence is num
        ? '${(confidence * 100).round()}%'
        : '—';

    return SingleChildScrollView(
      key: const ValueKey('result'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeader('Kết quả nhận diện', 'Phân tích hoàn tất'),
          const SizedBox(height: 18),
          if (_imageBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: double.infinity,
                height: 230,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(_imageBytes!, fit: BoxFit.contain),
                    CustomPaint(
                      painter: _DetectionOverlay(
                        result['detections'],
                        fit: BoxFit.contain,
                        imageWidth: result['image_width'] ?? 1,
                        imageHeight: result['image_height'] ?? 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Color(0xFF12313A), Color(0xFF142138)],
              ),
              border: Border.all(color: _cyan.withValues(alpha: 0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: _cyan, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'TỔNG GIÁ TRỊ NHẬN DIỆN',
                      style: TextStyle(
                        color: _cyan,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  converted,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  exchangeRate,
                  style: const TextStyle(
                    color: Color(0xFFB7C5D8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _metricCard(Icons.payments_outlined, 'Số tờ', '$count'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _metricCard(
                  Icons.verified_outlined,
                  'Độ tin cậy',
                  confidencePercent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _detailCard(
            icon: Icons.currency_exchange_rounded,
            title: 'Mệnh giá phát hiện',
            detail: detected,
          ),
          const SizedBox(height: 10),
          _detailCard(
            icon: Icons.public_rounded,
            title: 'Quốc gia / loại tiền nhận diện',
            detail: detectedCountries,
          ),
          const SizedBox(height: 10),
          _detailCard(
            icon: Icons.shield_outlined,
            title: 'Trạng thái AI',
            detail:
                '${result['security_check'] ?? 'Đã xử lý ảnh bằng model ONNX'}',
          ),
          const SizedBox(height: 20),
          _primaryButton(
            label: 'Quét tờ tiền khác',
            icon: Icons.document_scanner_rounded,
            onPressed: _openScanner,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _goHome,
              style: TextButton.styleFrom(foregroundColor: _muted),
              child: const Text('Về trang chủ'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageHeader(String title, String subtitle) {
    return Row(
      children: [
        IconButton(
          onPressed: _goHome,
          style: IconButton.styleFrom(
            backgroundColor: _panel,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        _brandMark(size: 38),
      ],
    );
  }

  Widget _brandMark({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: const LinearGradient(colors: [_cyan, Color(0xFF8875FF)]),
        boxShadow: [
          BoxShadow(color: _cyan.withValues(alpha: 0.2), blurRadius: 18),
        ],
      ),
      child: Icon(
        Icons.currency_exchange_rounded,
        color: _background,
        size: size * 0.58,
      ),
    );
  }

  Widget _backendBadge() {
    final color = _backendOnline == true
        ? const Color(0xFF66E3A4)
        : _backendOnline == false
        ? const Color(0xFFFF8C8C)
        : const Color(0xFFFFD27A);
    final label = _backendOnline == true
        ? 'AI sẵn sàng'
        : _backendOnline == false
        ? 'AI ngoại tuyến'
        : 'Đang kết nối';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
      ],
    );
  }

  Widget _stepCard(String number, IconData icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 13),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                number,
                style: const TextStyle(
                  color: Color(0xFF596A82),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(icon, color: _cyan, size: 21),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _cyan, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailCard({
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _cyan, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
                const SizedBox(height: 5),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorPanel(String error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF321C27),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF8C8C).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF9B9B),
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              error,
              style: const TextStyle(
                color: Color(0xFFFFDADA),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: onPressed == null
                ? [Colors.blueGrey, Colors.blueGrey]
                : [_cyan, const Color(0xFF8A7BFF)],
          ),
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 19),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          style: ElevatedButton.styleFrom(
            foregroundColor: _background,
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: _cyan.withValues(alpha: 0.35)),
          backgroundColor: _panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

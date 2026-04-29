import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:async';
import '../services/user_data_service.dart';
import '../services/local_mode_storage_service.dart';
import '../services/subscription_service.dart';
import '../utils/device_utils.dart';
import '../utils/font_utils.dart';
import '../widgets/windows_title_bar.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _subscriptionUrlController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _isFormValid = false;
  bool _isLocalMode = false;

  // 所有服务器地址
  static const List<Map<String, String>> serverList = [
    {"name": "主服务器", "url": "http://moontv2.yzc2682877414.cc.cd"},
    {"name": "本地备用", "url": "http://192.168.1.174:5895"},
  ];

  int _logoTapCount = 0;
  Timer? _tapTimer;

  @override
  void initState() {
    super.initState();
    _loadSavedUserData(); // 🔥 先加载数据，再加监听

    _urlController.addListener(_validateForm);
    _usernameController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);
    _subscriptionUrlController.addListener(_validateForm);
  }

  // 🔥 最终修复：永远记住账号密码，任何情况都不清空
  void _loadSavedUserData() async {
    final userData = await UserDataService.getAllUserData();

    // 服务器
    if (userData['serverUrl'] != null && userData['serverUrl']!.isNotEmpty) {
      _urlController.text = userData['serverUrl']!;
    } else {
      _urlController.text = serverList.first["url"]!;
    }

    // 用户名
    if (userData['username'] != null && userData['username']!.isNotEmpty) {
      _usernameController.text = userData['username']!;
    }

    // 密码 🔥 核心修复
    if (userData['password'] != null && userData['password']!.isNotEmpty) {
      _passwordController.text = userData['password']!;
    }

    // 订阅地址
    final subscriptionUrl = await LocalModeStorageService.getSubscriptionUrl();
    if (subscriptionUrl != null && subscriptionUrl.isNotEmpty) {
      _subscriptionUrlController.text = subscriptionUrl;
    }

    if (mounted) {
      setState(() {
        _validateForm();
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _subscriptionUrlController.dispose();
    _tapTimer?.cancel();
    super.dispose();
  }

  void _handleLogoTap() {
    _logoTapCount++;
    _tapTimer?.cancel();

    if (_logoTapCount >= 10) {
      setState(() {
        _isLocalMode = !_isLocalMode;
        _validateForm();
        _logoTapCount = 0;
      });
      _showToast(
        _isLocalMode ? '已切换到本地模式' : '已切换到服务器模式',
        const Color(0xFF27ae60),
      );
    } else {
      _tapTimer = Timer(const Duration(seconds: 1), () {
        setState(() {
          _logoTapCount = 0;
        });
      });
    }
  }

  void _validateForm() {
    setState(() {
      if (_isLocalMode) {
        _isFormValid = _subscriptionUrlController.text.isNotEmpty;
      } else {
        _isFormValid = _urlController.text.isNotEmpty &&
            _usernameController.text.isNotEmpty &&
            _passwordController.text.isNotEmpty;
      }
    });
  }

  void _handleSubmit() {
    if (_isLocalMode) {
      _handleLocalModeLogin();
    } else {
      _handleLogin();
    }
  }

  // 🔥 切换服务器：绝对不刷新、不丢密码
  void _showServerPicker() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            Text("选择服务器", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            SizedBox(height: 10),
            ...serverList.map((e) => ListTile(
              title: Text(e["name"]!),
              subtitle: Text(e["url"]!),
              onTap: () {
                _urlController.text = e["url"]!;
                Navigator.pop(ctx);
              },
            )),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalModeForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _subscriptionUrlController,
          style: FontUtils.poppins(
            fontSize: 16,
            color: const Color(0xFF2c3e50),
          ),
          decoration: InputDecoration(
            labelText: '订阅链接',
            labelStyle: FontUtils.poppins(
              color: const Color(0xFF7f8c8d),
              fontSize: 14,
            ),
            hintText: '请输入订阅链接',
            hintStyle: FontUtils.poppins(
              color: const Color(0xFFbdc3c7),
              fontSize: 16,
            ),
            prefixIcon: const Icon(
              Icons.link,
              color: Color(0xFF7f8c8d),
              size: 20,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.6),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请输入订阅链接';
            }
            return null;
          },
          onChanged: (value) => _validateForm(),
          onFieldSubmitted: (_) => _handleSubmit(),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed:
          (_isLoading || !_isFormValid) ? null : _handleLocalModeLogin,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isFormValid && !_isLoading
                ? const Color(0xFF2c3e50)
                : const Color(0xFFbdc3c7),
            foregroundColor: _isFormValid && !_isLoading
                ? Colors.white
                : const Color(0xFF7f8c8d),
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
            shadowColor: Colors.transparent,
          ),
          child: _isLoading
              ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '登录中...',
                style: FontUtils.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ],
          )
              : Text(
            '登录',
            style: FontUtils.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ],
    );
  }

  String _processUrl(String url) {
    String processedUrl = url.trim();
    if (processedUrl.endsWith('/')) {
      processedUrl = processedUrl.substring(0, processedUrl.length - 1);
    }
    return processedUrl;
  }

  String _parseCookies(http.Response response) {
    List<String> cookies = [];
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders != null) {
      final cookieParts = setCookieHeaders.split(';');
      if (cookieParts.isNotEmpty) {
        cookies.add(cookieParts[0].trim());
      }
    }
    return cookies.join('; ');
  }

  void _showToast(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: FontUtils.poppins(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleLogin() async {
    if (_formKey.currentState!.validate() && _isFormValid) {
      setState(() {
        _isLoading = true;
      });

      try {
        String baseUrl = _processUrl(_urlController.text);
        String loginUrl = '$baseUrl/api/login';

        final response = await http.post(
          Uri.parse(loginUrl),
          headers: {
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'username': _usernameController.text,
            'password': _passwordController.text,
          }),
        );

        setState(() {
          _isLoading = false;
        });

        switch (response.statusCode) {
          case 200:
            String cookies = _parseCookies(response);
            await UserDataService.saveUserData(
              serverUrl: baseUrl,
              username: _usernameController.text,
              password: _passwordController.text, // 🔥 保存密码
              cookies: cookies,
            );
            await UserDataService.saveIsLocalMode(false);

            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const HomeScreen()),
                    (route) => false,
              );
            }
            break;
          case 401:
            _showToast('用户名或密码错误', const Color(0xFFe74c3c));
            break;
          case 500:
            _showToast('服务器错误', const Color(0xFFe74c3c));
            break;
          default:
            _showToast('网络异常', const Color(0xFFe74c3c));
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        _showToast('网络异常', const Color(0xFFe74c3c));
      }
    }
  }

  void _handleLocalModeLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final newUrl = _subscriptionUrlController.text.trim();
        final response = await http.get(Uri.parse(newUrl));

        if (response.statusCode != 200) {
          setState(() {
            _isLoading = false;
          });
          _showToast('获取订阅内容失败', const Color(0xFFe74c3c));
          return;
        }

        final content =
        await SubscriptionService.parseSubscriptionContent(response.body);

        if (content == null ||
            (content.searchResources == null || content.searchResources!.isEmpty) &&
                (content.liveSources == null || content.liveSources!.isEmpty)) {
          setState(() {
            _isLoading = false;
          });
          _showToast('解析订阅内容失败', const Color(0xFFe74c3c));
          return;
        }

        final existingUrl = await LocalModeStorageService.getSubscriptionUrl();

        if (existingUrl != null &&
            existingUrl.isNotEmpty &&
            existingUrl != newUrl) {
          setState(() {
            _isLoading = false;
          });

          if (!mounted) return;

          final shouldClear = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                '提示',
                style: FontUtils.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2c3e50),
                ),
              ),
              content: Text(
                '检测到已有本地模式内容且订阅链接不一致，是否清空全部本地模式存储？',
                style: FontUtils.poppins(
                  fontSize: 14,
                  color: const Color(0xFF2c3e50),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    '否',
                    style: FontUtils.poppins(
                      fontSize: 14,
                      color: const Color(0xFF7f8c8d),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    '是',
                    style: FontUtils.poppins(
                      fontSize: 14,
                      color: const Color(0xFFe74c3c),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );

          if (shouldClear == true) {
            await LocalModeStorageService.clearAllLocalModeData();
          } else if (shouldClear == null) {
            return;
          }

          setState(() {
            _isLoading = true;
          });
        }

        await LocalModeStorageService.saveSubscriptionUrl(newUrl);
        if (content.searchResources != null && content.searchResources!.isNotEmpty) {
          await LocalModeStorageService.saveSearchSources(content.searchResources!);
        }
        if (content.liveSources != null && content.liveSources!.isNotEmpty) {
          await LocalModeStorageService.saveLiveSources(content.liveSources!);
        }

        await UserDataService.saveIsLocalMode(true);

        setState(() {
          _isLoading = false;
        });

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false,
          );
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        _showToast('登录失败：${e.toString()}', const Color(0xFFe74c3c));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = DeviceUtils.isTablet(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFe6f3fb),
              Color(0xFFeaf3f7),
              Color(0xFFf7f7f3),
              Color(0xFFe9ecef),
              Color(0xFFdbe3ea),
              Color(0xFFd3dde6),
            ],
            stops: [0.0, 0.18, 0.38, 0.60, 0.80, 1.0],
          ),
        ),
        child: Column(
          children: [
            if (Platform.isWindows) const WindowsTitleBar(forceBlack: true),
            Expanded(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 0 : 32.0,
                      vertical: 24.0,
                    ),
                    child:
                    isTablet ? _buildTabletLayout() : _buildMobileLayout(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _handleLogoTap,
          child: Text(
            'Selene',
            style: FontUtils.sourceCodePro(
              fontSize: 42,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF2c3e50),
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 40),
        Form(
          key: _formKey,
          child: _isLocalMode
              ? _buildLocalModeForm()
              : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _urlController,
                style: FontUtils.poppins(
                  fontSize: 16,
                  color: const Color(0xFF2c3e50),
                ),
                decoration: InputDecoration(
                  labelText: '服务器地址',
                  labelStyle: FontUtils.poppins(
                    color: const Color(0xFF7f8c8d),
                    fontSize: 14,
                  ),
                  hintText: 'https://example.com',
                  hintStyle: FontUtils.poppins(
                    color: const Color(0xFFbdc3c7),
                    fontSize: 16,
                  ),
                  prefixIcon: const Icon(
                    Icons.link,
                    color: Color(0xFF7f8c8d),
                    size: 20,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.6),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入服务器地址';
                  }
                  final uri = Uri.tryParse(value);
                  if (uri == null ||
                      uri.scheme.isEmpty ||
                      uri.host.isEmpty) {
                    return '请输入有效的URL地址';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _handleSubmit(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _showServerPicker,
                  child: Text("选择服务器"),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                style: FontUtils.poppins(
                  fontSize: 16,
                  color: const Color(0xFF2c3e50),
                ),
                decoration: InputDecoration(
                  labelText: '用户名',
                  labelStyle: FontUtils.poppins(
                    color: const Color(0xFF7f8c8d),
                    fontSize: 14,
                  ),
                  hintText: '请输入用户名',
                  hintStyle: FontUtils.poppins(
                    color: const Color(0xFFbdc3c7),
                    fontSize: 16,
                  ),
                  prefixIcon: const Icon(
                    Icons.person,
                    color: Color(0xFF7f8c8d),
                    size: 20,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.6),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入用户名';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _handleSubmit(),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                style: FontUtils.poppins(
                  fontSize: 16,
                  color: const Color(0xFF2c3e50),
                ),
                decoration: InputDecoration(
                  labelText: '密码',
                  labelStyle: FontUtils.poppins(
                    color: const Color(0xFF7f8c8d),
                    fontSize: 14,
                  ),
                  hintText: '请输入密码',
                  hintStyle: FontUtils.poppins(
                    color: const Color(0xFFbdc3c7),
                    fontSize: 16,
                  ),
                  prefixIcon: const Icon(
                    Icons.lock,
                    color: Color(0xFF7f8c8d),
                    size: 20,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: const Color(0xFF7f8c8d),
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.6),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入密码';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _handleSubmit(),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed:
                (_isLoading || !_isFormValid) ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isFormValid && !_isLoading
                      ? const Color(0xFF2c3e50)
                      : const Color(0xFFbdc3c7),
                  foregroundColor: _isFormValid && !_isLoading
                      ? Colors.white
                      : const Color(0xFF7f8c8d),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                child: _isLoading
                    ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '登录中...',
                      style: FontUtils.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                )
                    : Text(
                  '登录',
                  style: FontUtils.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _handleLogoTap,
            child: Text(
              'Selene',
              style: FontUtils.sourceCodePro(
                fontSize: 42,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF2c3e50),
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 40),
          Form(
            key: _formKey,
            child: _isLocalMode
                ? _buildLocalModeForm()
                : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _urlController,
                  style: FontUtils.poppins(
                    fontSize: 16,
                    color: const Color(0xFF2c3e50),
                  ),
                  decoration: InputDecoration(
                    labelText: '服务器地址',
                    labelStyle: FontUtils.poppins(
                      color: const Color(0xFF7f8c8d),
                      fontSize: 14,
                    ),
                    hintText: 'https://example.com',
                    hintStyle: FontUtils.poppins(
                      color: const Color(0xFFbdc3c7),
                      fontSize: 16,
                    ),
                    prefixIcon: const Icon(
                      Icons.link,
                      color: Color(0xFF7f8c8d),
                      size: 20,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.6),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入服务器地址';
                    }
                    final uri = Uri.tryParse(value);
                    if (uri == null ||
                        uri.scheme.isEmpty ||
                        uri.host.isEmpty) {
                      return '请输入有效的URL地址';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _handleSubmit(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showServerPicker,
                    child: Text("选择服务器"),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _usernameController,
                  style: FontUtils.poppins(
                    fontSize: 16,
                    color: const Color(0xFF2c3e50),
                  ),
                  decoration: InputDecoration(
                    labelText: '用户名',
                    labelStyle: FontUtils.poppins(
                      color: const Color(0xFF7f8c8d),
                      fontSize: 14,
                    ),
                    hintText: '请输入用户名',
                    hintStyle: FontUtils.poppins(
                      color: const Color(0xFFbdc3c7),
                      fontSize: 16,
                    ),
                    prefixIcon: const Icon(
                      Icons.person,
                      color: Color(0xFF7f8c8d),
                      size: 20,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.6),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入用户名';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _handleSubmit(),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  style: FontUtils.poppins(
                    fontSize: 16,
                    color: const Color(0xFF2c3e50),
                  ),
                  decoration: InputDecoration(
                    labelText: '密码',
                    labelStyle: FontUtils.poppins(
                      color: const Color(0xFF7f8c8d),
                      fontSize: 14,
                    ),
                    hintText: '请输入密码',
                    hintStyle: FontUtils.poppins(
                      color: const Color(0xFFbdc3c7),
                    ),
                    prefixIcon: const Icon(
                      Icons.lock,
                      color: Color(0xFF7f8c8d),
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: const Color(0xFF7f8c8d),
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.6),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入密码';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _handleSubmit(),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed:
                  (_isLoading || !_isFormValid) ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isFormValid && !_isLoading
                        ? const Color(0xFF2c3e50)
                        : const Color(0xFFbdc3c7),
                    foregroundColor: _isFormValid && !_isLoading
                        ? Colors.white
                        : const Color(0xFF7f8c8d),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                  child: _isLoading
                      ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '登录中...',
                        style: FontUtils.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  )
                      : Text(
                    '登录',
                    style: FontUtils.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
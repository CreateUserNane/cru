import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _apiBaseOverride = String.fromEnvironment('API_BASE_URL');
String get _apiBase {
  if (_apiBaseOverride.isNotEmpty) return _apiBaseOverride;
  final platform = defaultTargetPlatform;
  if (kIsWeb ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux) {
    return 'http://localhost:8000/api';
  }
  return 'http://10.0.2.2:8000/api';
}

const _tokenKey = 'cru_api_token';
const _canvas = Color(0xfff2f3f7);
const _surface = Color(0xffffffff);
const _ink = Color(0xff202638);
const _muted = Color(0xff687083);
const _line = Color(0xffd9dde6);
const _accent = Color(0xff3d58a8);
const _danger = Color(0xffa43e45);

class CruUser {
  const CruUser({required this.username, required this.email});
  final String username;
  final String email;
  factory CruUser.fromJson(Map<String, dynamic> json) => CruUser(
    username: json['username'] as String,
    email: json['email'] as String,
  );
}

class AuthApi {
  static const _storage = FlutterSecureStorage();
  final _client = http.Client();

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool auth = false,
  }) async {
    final uri = Uri.parse('$_apiBase/$path');
    final token = auth ? await _storage.read(key: _tokenKey) : null;
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final response = switch (method) {
      'POST' => await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      ),
      'PUT' => await _client.put(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      ),
      _ => await _client.get(uri, headers: headers),
    };
    final data = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errors = data['errors'] as Map<String, dynamic>?;
      final field = errors?.keys.first;
      final details = field == null ? null : errors?[field];
      final message = details is List && details.isNotEmpty
          ? details.first.toString()
          : (data['message'] ?? 'Request failed.').toString();
      if ((field == 'name' || field == 'username') &&
          message.contains('required')) {
        throw Exception('Enter a username to continue.');
      }
      throw Exception(
        message.replaceAll('The name field', 'The username field'),
      );
    }
    return data;
  }

  Future<CruUser?> restore() async {
    if (await _storage.read(key: _tokenKey) == null) return null;
    try {
      final data = await _request('user', auth: true);
      return CruUser.fromJson(data['user'] as Map<String, dynamic>);
    } catch (_) {
      await _storage.delete(key: _tokenKey);
      return null;
    }
  }

  Future<CruUser> _authenticate(String path, Map<String, dynamic> body) async {
    final data = await _request(path, method: 'POST', body: body);
    await _storage.write(key: _tokenKey, value: data['token'] as String);
    return CruUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<CruUser> signup(String username, String email, String password) async {
    final data = await _request(
      'register',
      method: 'POST',
      body: {'username': username, 'email': email, 'password': password},
    );
    return CruUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<CruUser> login(String email, String password) =>
      _authenticate('login', {'email': email, 'password': password});

  Future<CruUser> update(
    String username,
    String email,
    String? password,
  ) async {
    final body = <String, dynamic>{'username': username, 'email': email};
    if (password != null && password.isNotEmpty) body['password'] = password;
    final data = await _request('user', method: 'PUT', body: body, auth: true);
    return CruUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      await _request('logout', method: 'POST', auth: true);
    } finally {
      await _storage.delete(key: _tokenKey);
    }
  }
}

void main() => runApp(const CruApp());

class CruApp extends StatefulWidget {
  const CruApp({super.key});

  @override
  State<CruApp> createState() => _CruAppState();
}

class _CruAppState extends State<CruApp> {
  final _api = AuthApi();
  CruUser? _user;
  bool _loading = true;
  bool _hasAccount = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final user = await _api.restore();
    if (mounted)
      setState(() {
        _user = user;
        _loading = false;
      });
  }

  Future<void> _createAccount(
    String name,
    String email,
    String password,
  ) async {
    await _api.signup(name, email, password);
    if (mounted)
      setState(() {
        _hasAccount = true;
      });
  }

  Future<void> _signIn(String email, String password) async {
    final user = await _api.login(email, password);
    if (mounted)
      setState(() {
        _user = user;
        _hasAccount = true;
      });
  }

  Future<void> _updateProfile(
    String name,
    String email,
    String? password,
  ) async {
    final user = await _api.update(name, email, password);
    if (mounted) setState(() => _user = user);
  }

  Future<void> _signOut() async {
    try {
      await _api.logout();
    } finally {
      if (mounted) setState(() => _user = null);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'cru',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.light,
      ),
    ),
    home: _loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : _user != null
        ? ProfileScreen(
            user: _user!,
            onSave: _updateProfile,
            onSignOut: _signOut,
          )
        : AuthScreen(
            onCreate: _createAccount,
            onSignIn: _signIn,
            hasAccount: _hasAccount,
          ),
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.onCreate,
    required this.onSignIn,
    required this.hasAccount,
  });
  final Future<void> Function(String, String, String) onCreate;
  final Future<void> Function(String, String) onSignIn;
  final bool hasAccount;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _signup = false;
  bool _showPassword = false;
  bool _busy = false;
  String? _error;
  String? _success;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _signup = !widget.hasAccount;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      if (_signup) {
        await widget.onCreate(
          _name.text.trim(),
          _email.text.trim(),
          _password.text,
        );
        if (mounted) {
          setState(() {
            _signup = false;
            _password.clear();
            _success = 'Account created. Log in to continue.';
          });
        }
      } else {
        await widget.onSignIn(_email.text.trim(), _password.text);
      }
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _canvas,
    body: LiquidStage(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Brand(),
                  const SizedBox(height: 58),
                  Text(
                    _signup ? 'Create account' : 'Sign in',
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 36,
                      height: 1.08,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _signup
                        ? 'Set up your cru profile.'
                        : 'Manage your cru profile.',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_signup) ...[
                          _Field(
                            controller: _name,
                            label: 'Username',
                            validator: (value) =>
                                (value == null || value.trim().length < 2)
                                ? 'Enter at least 2 characters.'
                                : null,
                          ),
                          const SizedBox(height: 18),
                        ],
                        _Field(
                          controller: _email,
                          label: 'Email address',
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) =>
                              (value == null ||
                                  !value.contains('@') ||
                                  !value.contains('.'))
                              ? 'Enter a valid email address.'
                              : null,
                        ),
                        const SizedBox(height: 18),
                        _Field(
                          controller: _password,
                          label: 'Password',
                          obscure: !_showPassword,
                          suffix: IconButton(
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 19,
                              color: _muted,
                            ),
                          ),
                          validator: (value) =>
                              (value == null || value.length < 6)
                              ? 'Use at least 6 characters.'
                              : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: _danger,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        if (_success != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _success!,
                            style: const TextStyle(
                              color: Color(0xff367258),
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 26),
                        _PrimaryButton(
                          label: _signup ? 'Create account' : 'Log in',
                          onPressed: _submit,
                          busy: _busy,
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _signup ? 'Already registered? ' : 'New to cru? ',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 14,
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _signup = !_signup;
                                _error = null;
                                _success = null;
                              }),
                              style: TextButton.styleFrom(
                                foregroundColor: _accent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                _signup ? 'Log in' : 'Create account',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.user,
    required this.onSave,
    required this.onSignOut,
  });
  final CruUser user;
  final Future<void> Function(String, String, String?) onSave;
  final Future<void> Function() onSignOut;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _name = TextEditingController(text: widget.user.username);
  late final _email = TextEditingController(text: widget.user.email);
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _editing = false;
  bool _saving = false;
  String? _notice;
  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        _name.text.trim(),
        _email.text.trim(),
        _password.text,
      );
      if (mounted)
        setState(() {
          _editing = false;
          _notice = 'Your details are up to date.';
          _password.clear();
        });
    } catch (error) {
      if (mounted)
        setState(
          () => _notice = error.toString().replaceFirst('Exception: ', ''),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: LiquidStage(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Brand(),
                    const SizedBox(height: 54),
                    Row(
                      children: [
                        LiquidGlass(
                          radius: 16,
                          child: SizedBox(
                            width: 54,
                            height: 54,
                            child: Center(
                              child: Text(
                                widget.user.username[0].toUpperCase(),
                                style: const TextStyle(
                                  color: _accent,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.user.username,
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.user.email,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Text(
                      'Account details',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 29,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _editing
                          ? 'Update your login details.'
                          : 'Your profile information.',
                      style: const TextStyle(color: _muted, fontSize: 15),
                    ),
                    const SizedBox(height: 30),
                    Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Field(
                            controller: _name,
                            label: 'Username',
                            enabled: _editing,
                            validator: (value) =>
                                (value == null || value.trim().length < 2)
                                ? 'Enter at least 2 characters.'
                                : null,
                          ),
                          const SizedBox(height: 18),
                          _Field(
                            controller: _email,
                            label: 'Email address',
                            enabled: _editing,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) =>
                                (value == null ||
                                    !value.contains('@') ||
                                    !value.contains('.'))
                                ? 'Enter a valid email address.'
                                : null,
                          ),
                          if (_editing) ...[
                            const SizedBox(height: 18),
                            _Field(
                              controller: _password,
                              label: 'New password (optional)',
                              obscure: true,
                              validator: (value) =>
                                  (value != null &&
                                      value.isNotEmpty &&
                                      value.length < 6)
                                  ? 'Use at least 6 characters.'
                                  : null,
                            ),
                          ],
                          if (_notice != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _notice!,
                              style: TextStyle(
                                color: _notice!.contains('up to date')
                                    ? const Color(0xff367258)
                                    : _danger,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: 26),
                          if (_editing)
                            Row(
                              children: [
                                Expanded(
                                  child: _PrimaryButton(
                                    label: 'Save changes',
                                    icon: Icons.check_rounded,
                                    onPressed: _save,
                                    busy: _saving,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton(
                                  onPressed: () => setState(() {
                                    _editing = false;
                                    _name.text = widget.user.username;
                                    _email.text = widget.user.email;
                                    _password.clear();
                                  }),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _ink,
                                    side: const BorderSide(color: _line),
                                    minimumSize: const Size(52, 54),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Icon(Icons.close_rounded),
                                ),
                              ],
                            )
                          else
                            _PrimaryButton(
                              label: 'Edit account',
                              icon: Icons.edit_outlined,
                              onPressed: () => setState(() {
                                _editing = true;
                                _notice = null;
                              }),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Divider(height: 1, color: _line),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: widget.onSignOut,
                        icon: const Icon(Icons.logout_rounded, size: 17),
                        label: const Text('Log out'),
                        style: TextButton.styleFrom(
                          foregroundColor: _muted,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.start,
    children: [
      LiquidGlass(
        radius: 10,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: Text(
              'c',
              style: const TextStyle(
                color: _accent,
                fontSize: 22,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      const Text(
        'cru',
        style: TextStyle(
          color: _ink,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
      ),
    ],
  );
}

class LiquidStage extends StatelessWidget {
  const LiquidStage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const Positioned.fill(child: CustomPaint(painter: _AtmospherePainter())),
      child,
    ],
  );
}

class _AtmospherePainter extends CustomPainter {
  const _AtmospherePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawColor(const Color(0xff090e21), BlendMode.src);

    // A luminous navigation field keeps the center legible while color gathers
    // toward the edges like a lit instrument chamber.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * .5, size.height * .48),
          size.height * .67,
          [
            const Color(0xffedf1fb),
            const Color(0xffdce4f5),
            const Color(0xff6178bd).withValues(alpha: .84),
            const Color(0xff17234a).withValues(alpha: .38),
          ],
          const [0, .58, .88, 1],
        ),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * .96, size.height * .06),
          size.width * .62,
          [const Color(0xff12c9ee).withValues(alpha: .72), Colors.transparent],
        ),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * .02, size.height * .91),
          size.width * .72,
          [const Color(0xff8056ef).withValues(alpha: .58), Colors.transparent],
        ),
    );

    // Instrument-grid arcs and orbital tracks frame the quiet form area.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeWidth = 1.4
      ..color = const Color(0xff455a9c).withValues(alpha: .58);
    final fineTrack = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..strokeWidth = 1
      ..color = const Color(0xff16aeca).withValues(alpha: .62);
    final upperOrbit = Rect.fromCenter(
      center: Offset(size.width * 1.02, size.height * .10),
      width: size.width * .74,
      height: size.width * .74,
    );
    canvas.drawArc(upperOrbit, 2.05, 1.45, false, track);
    canvas.drawArc(upperOrbit.deflate(15), 2.08, 1.39, false, fineTrack);
    canvas.drawArc(upperOrbit.deflate(31), 2.12, 1.32, false, track);

    final lowerOrbit = Rect.fromCenter(
      center: Offset(size.width * -.10, size.height * .90),
      width: size.width * .58,
      height: size.width * .58,
    );
    canvas.drawArc(lowerOrbit, 5.12, 1.30, false, track);
    canvas.drawArc(lowerOrbit.deflate(14), 5.18, 1.22, false, fineTrack);

    final gridPaint = Paint()
      ..color = const Color(0xff334983).withValues(alpha: .26)
      ..strokeWidth = .8;
    final gridOrigin = Offset(size.width * .86, size.height * .17);
    for (var i = 0; i < 5; i++) {
      final x = gridOrigin.dx + i * 14.0;
      final y = gridOrigin.dy + i * 14.0;
      canvas.drawLine(
        Offset(x, gridOrigin.dy),
        Offset(x, gridOrigin.dy + 56),
        gridPaint,
      );
      canvas.drawLine(
        Offset(gridOrigin.dx, y),
        Offset(gridOrigin.dx + 56, y),
        gridPaint,
      );
    }

    final nodePaint = Paint()
      ..color = const Color(0xff04b8d9).withValues(alpha: .92);
    for (final point in [
      Offset(size.width * .79, size.height * .10),
      Offset(size.width * .92, size.height * .20),
      Offset(size.width * .11, size.height * .84),
    ]) {
      canvas.drawCircle(point, 3, nodePaint);
      canvas.drawCircle(
        point,
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7
          ..color = const Color(0xff22b9d8).withValues(alpha: .32),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) => false;
}

class LiquidGlass extends StatefulWidget {
  const LiquidGlass({super.key, required this.child, this.radius = 16});

  final Widget child;
  final double radius;

  static final Future<ui.FragmentProgram> _program =
      ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    try {
      final program = await LiquidGlass._program;
      final shader = program.fragmentShader();
      shader.setFloat(2, 4.5);
      shader.setFloat(3, 0.65);
      if (!mounted) {
        shader.dispose();
        return;
      }
      setState(() => _shader = shader);
    } catch (_) {
      // Keep the light refraction fallback on unsupported rendering backends.
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    final filter = shader == null
        ? ui.ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2)
        : ui.ImageFilter.shader(shader);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: filter,
              child: const SizedBox.expand(),
            ),
          ),
          CustomPaint(
            painter: _LiquidEdgePainter(radius: widget.radius),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _LiquidEdgePainter extends CustomPainter {
  const _LiquidEdgePainter({required this.radius});
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    canvas.drawRRect(
      shape,
      Paint()..color = const Color(0xfff7f9ff).withValues(alpha: .18),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: .72),
    );

    final highlight = Path()
      ..moveTo(radius, 1)
      ..cubicTo(
        size.width * .28,
        1,
        size.width * .5,
        1.5,
        size.width * .72,
        2.2,
      );
    canvas.drawPath(
      highlight,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = ui.Gradient.linear(
          Offset(radius, 1),
          Offset(size.width * .78, 2),
          [
            Colors.white.withValues(alpha: .9),
            Colors.white.withValues(alpha: .08),
          ],
        ),
    );

    final lowerEdge = Path()
      ..moveTo(radius, size.height - 1)
      ..quadraticBezierTo(
        size.width * .5,
        size.height + .5,
        size.width - radius,
        size.height - 1,
      );
    canvas.drawPath(
      lowerEdge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xff586783).withValues(alpha: .22),
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidEdgePainter oldDelegate) =>
      oldDelegate.radius != radius;
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.validator,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscure, enabled;
  final Widget? suffix;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    validator: validator,
    keyboardType: keyboardType,
    obscureText: obscure,
    enabled: enabled,
    style: const TextStyle(
      fontSize: 15,
      color: _ink,
      fontWeight: FontWeight.w500,
    ),
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: suffix,
      filled: true,
      fillColor: _surface,
      labelStyle: const TextStyle(color: _muted, fontSize: 14),
      floatingLabelStyle: const TextStyle(color: _accent, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.3),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _line),
      ),
      errorStyle: const TextStyle(color: _danger, fontSize: 12, height: 1.2),
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool busy;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: LiquidGlass(
      radius: 14,
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: busy ? null : onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _accent,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (icon != null) ...[
                          const SizedBox(width: 8),
                          Icon(icon, size: 18, color: _accent),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

import 'dart:ui';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/api',
);
const _tokenKey = 'cru_api_token';

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
      final detail = errors?.values.firstOrNull;
      throw Exception(
        detail is List
            ? detail.first.toString()
            : (data['message'] ?? 'Request failed.').toString(),
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

  Future<CruUser> signup(String username, String email, String password) =>
      _authenticate('register', {
        'username': username,
        'email': email,
        'password': password,
      });
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
    final user = await _api.signup(name, email, password);
    if (mounted)
      setState(() {
        _user = user;
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
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff0a0c16),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffa9b6ff),
        brightness: Brightness.dark,
      ),
      fontFamily: 'SF Pro Display',
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

const _ink = Color(0xff0a0c16);
const _lavender = Color(0xffc6caff);
const _muted = Color(0xffa0a2b2);

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
    });
    try {
      if (_signup) {
        await widget.onCreate(
          _name.text.trim(),
          _email.text.trim(),
          _password.text,
        );
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
    body: GlassBackdrop(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Brand(),
                    const SizedBox(height: 42),
                    GlassCard(
                      padding: const EdgeInsets.fromLTRB(26, 30, 26, 26),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _signup ? 'A little more you.' : 'Welcome back.',
                              style: const TextStyle(
                                fontSize: 29,
                                height: 1.1,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _signup
                                  ? 'Create your space. Keep it yours.'
                                  : 'Your space is right where you left it.',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 28),
                            if (_signup) ...[
                              _Field(
                                controller: _name,
                                label: 'Username',
                                icon: Icons.person_outline_rounded,
                                validator: (v) =>
                                    (v == null || v.trim().length < 2)
                                    ? 'Enter at least 2 characters'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                            ],
                            _Field(
                              controller: _email,
                              label: 'Email address',
                              icon: Icons.mail_outline_rounded,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) =>
                                  (v == null ||
                                      !v.contains('@') ||
                                      !v.contains('.'))
                                  ? 'Enter a valid email address'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            _Field(
                              controller: _password,
                              label: 'Password',
                              icon: Icons.lock_outline_rounded,
                              obscure: !_showPassword,
                              suffix: IconButton(
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 19,
                                  color: _muted,
                                ),
                              ),
                              validator: (v) => (v == null || v.length < 6)
                                  ? 'Use at least 6 characters'
                                  : null,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xffffa7aa),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            _PrimaryButton(
                              label: _signup ? 'Create account' : 'Log in',
                              icon: Icons.arrow_forward_rounded,
                              onPressed: _submit,
                              busy: _busy,
                            ),
                            const SizedBox(height: 20),
                            Center(
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                children: [
                                  Text(
                                    _signup
                                        ? 'Already have an account? '
                                        : 'New to cru? ',
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      _signup = !_signup;
                                      _error = null;
                                    }),
                                    child: Text(
                                      _signup ? 'Log in' : 'Create account',
                                      style: const TextStyle(
                                        color: _lavender,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Center(
                      child: Text(
                        'YOUR ACCOUNT. YOUR CALL.',
                        style: TextStyle(
                          color: Color(0xff77798c),
                          fontSize: 10,
                          letterSpacing: 2.2,
                          fontWeight: FontWeight.w600,
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
      body: GlassBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Brand(),
                    const SizedBox(height: 40),
                    GlassCard(
                      padding: const EdgeInsets.all(26),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xffb7c0ff),
                                    Color(0xff8278c9),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xffa4aaff)
                                        .withOpacity(.24),
                                    blurRadius: 30,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  widget.user.username.isEmpty
                                      ? 'C'
                                      : widget.user.username[0].toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 27,
                                    color: _ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'Your space.',
                              style: TextStyle(
                                fontSize: 29,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.8,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _editing
                                  ? 'Make it feel like you.'
                                  : 'Everything in its right place.',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 28),
                            _Field(
                              controller: _name,
                              label: 'Username',
                              icon: Icons.person_outline_rounded,
                              enabled: _editing,
                              validator: (v) =>
                                  (v == null || v.trim().length < 2)
                                  ? 'Enter at least 2 characters'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            _Field(
                              controller: _email,
                              label: 'Email address',
                              icon: Icons.mail_outline_rounded,
                              enabled: _editing,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) =>
                                  (v == null ||
                                      !v.contains('@') ||
                                      !v.contains('.'))
                                  ? 'Enter a valid email address'
                                  : null,
                            ),
                            if (_editing) ...[
                              const SizedBox(height: 14),
                              _Field(
                                controller: _password,
                                label: 'New password (optional)',
                                icon: Icons.lock_outline_rounded,
                                obscure: true,
                                validator: (v) =>
                                    (v != null && v.isNotEmpty && v.length < 6)
                                    ? 'Use at least 6 characters'
                                    : null,
                              ),
                            ],
                            if (_notice != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _notice!,
                                style: const TextStyle(
                                  color: Color(0xffb7e8d5),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
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
                                  const SizedBox(width: 10),
                                  IconButton(
                                    onPressed: () => setState(() {
                                      _editing = false;
                                      _name.text = widget.user.username;
                                      _email.text = widget.user.email;
                                      _password.clear();
                                    }),
                                    icon: const Icon(Icons.close_rounded),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white.withOpacity(
                                        .07,
                                      ),
                                      minimumSize: const Size(50, 50),
                                    ),
                                  ),
                                ],
                              )
                            else
                              _PrimaryButton(
                                label: 'Edit account',
                                icon: Icons.tune_rounded,
                                onPressed: () => setState(() {
                                  _editing = true;
                                  _notice = null;
                                }),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: widget.onSignOut,
                      icon: const Icon(Icons.logout_rounded, size: 17),
                      label: const Text('Log out'),
                      style: TextButton.styleFrom(foregroundColor: _muted),
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
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffe3e6ff), Color(0xff989be7)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xffaab0ff).withOpacity(.25),
              blurRadius: 20,
            ),
          ],
        ),
        child: const Icon(Icons.waves_rounded, color: _ink, size: 23),
      ),
      const SizedBox(width: 11),
      const Text(
        'cru',
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w600,
          letterSpacing: -.8,
        ),
      ),
    ],
  );
}

class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.8, -.85),
            radius: 1.2,
            colors: [Color(0xff242542), _ink, Color(0xff090b14)],
          ),
        ),
      ),
      Positioned(
        top: -80,
        right: -90,
        child: _Glow(
          size: 290,
          color: const Color(0xff6d65d9).withOpacity(.28),
        ),
      ),
      Positioned(
        bottom: -110,
        left: -80,
        child: _Glow(
          size: 310,
          color: const Color(0xff426b9d).withOpacity(.22),
        ),
      ),
      child,
    ],
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ImageFiltered(
    imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ),
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, required this.padding});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(30),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.075),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.16),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.validator,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
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
    style: const TextStyle(fontSize: 14, color: Color(0xfff5f5fa)),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 19),
      suffixIcon: suffix,
      filled: true,
      fillColor: enabled
          ? Colors.white.withOpacity(.045)
          : Colors.white.withOpacity(.025),
      labelStyle: const TextStyle(color: Color(0xffa0a2b2), fontSize: 13),
      prefixIconColor: const Color(0xffbcbfe2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(.09)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xffbfc5ff), width: 1.2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(.055)),
      ),
      errorStyle: const TextStyle(fontSize: 11, height: 1.2),
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool busy;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xffdce0ff), Color(0xffaeb6f7)],
        ),
        borderRadius: BorderRadius.circular(17),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff999ff4).withOpacity(.24),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2, color: _ink),
              )
            : Icon(icon, size: 19),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          foregroundColor: _ink,
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
      ),
    ),
  );
}

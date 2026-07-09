/// Resolves the active TBA API key for an outgoing request.
///
/// Two implementations are provided here:
///
/// 1. [CompileTimeTbaConfig] — reads `String.fromEnvironment('TBA_API_KEY')`,
///    which is populated by `--dart-define=TBA_API_KEY=...` or
///    `--dart-define-from-file=tba.env` at build/run time. This is the default
///    used by the app.
///
/// 2. [InMemoryTbaConfig] — holds a key in memory; used by tests.
abstract class TbaConfig {
  Future<String?> resolveApiKey();
}

class CompileTimeTbaConfig implements TbaConfig {
  const CompileTimeTbaConfig();

  static const String _compileTimeKey = String.fromEnvironment('TBA_API_KEY');

  @override
  Future<String?> resolveApiKey() async {
    if (_compileTimeKey.isEmpty) {
      return null;
    }
    return _compileTimeKey;
  }
}

class InMemoryTbaConfig implements TbaConfig {
  InMemoryTbaConfig([this._key]);

  String? _key;

  @override
  Future<String?> resolveApiKey() async => _key;

  set apiKey(String? value) {
    _key = value;
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_provider.dart';

/// AI 제공사별 API 키(민감정보)는 기기 키체인/키스토어(flutter_secure_storage)에,
/// 어떤 제공사를 쓸지/모델명 같은 비민감 설정은 shared_preferences에 나눠 저장한다.
/// API 키는 서버로 전송되지 않고 이 기기에만 보관되며, 각 제공사 API를 호출할
/// 때만 사용자 본인의 키로 직접 호출한다.
class AiCredentialsRepository extends ChangeNotifier {
  static const _activeProviderKey = 'ai_active_provider_v1';
  static const _modelPrefix = 'ai_model_v1_';
  static const _secureKeyPrefix = 'ai_api_key_v1_';

  final FlutterSecureStorage _secureStorage;

  AiProvider? _activeProvider;
  final Map<AiProvider, String> _apiKeys = {};
  final Map<AiProvider, String> _models = {};
  bool _isLoaded = false;

  AiCredentialsRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage() {
    _load();
  }

  bool get isLoaded => _isLoaded;
  AiProvider? get activeProvider => _activeProvider;

  bool hasKey(AiProvider provider) => (_apiKeys[provider] ?? '').isNotEmpty;

  /// 최소한 하나의 제공사라도 연동돼 있는지 — 브리핑 화면에서 "AI 연동 필요"
  /// 안내를 보여줄지 판단하는 데 쓴다.
  bool get hasAnyConnection => _apiKeys.values.any((k) => k.isNotEmpty);

  String? apiKeyFor(AiProvider provider) => _apiKeys[provider];

  String modelFor(AiProvider provider) => _models[provider] ?? provider.defaultModel;

  /// 마스킹된 키 미리보기 — 설정 화면에서 이미 저장된 키를 다시 평문으로
  /// 보여주지 않기 위함(예: "sk-ant-...a1b2").
  String? maskedKeyPreview(AiProvider provider) {
    final key = _apiKeys[provider];
    if (key == null || key.isEmpty) return null;
    if (key.length <= 8) return '••••${key.substring(key.length - 2)}';
    return '${key.substring(0, 6)}...${key.substring(key.length - 4)}';
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeName = prefs.getString(_activeProviderKey);
      if (activeName != null) {
        final matches = AiProvider.values.where((p) => p.name == activeName);
        _activeProvider = matches.isEmpty ? null : matches.first;
      }
      for (final provider in AiProvider.values) {
        final model = prefs.getString('$_modelPrefix${provider.name}');
        if (model != null && model.trim().isNotEmpty) _models[provider] = model;

        final key = await _secureStorage.read(key: '$_secureKeyPrefix${provider.name}');
        if (key != null && key.trim().isNotEmpty) _apiKeys[provider] = key;
      }
    } catch (e) {
      debugPrint('Error loading AI credentials: $e');
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> setApiKey(AiProvider provider, String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await removeApiKey(provider);
      return;
    }
    _apiKeys[provider] = trimmed;
    // 처음 연동하는 제공사면 자동으로 활성 제공사로 지정 — 사용자가 굳이
    // 다시 "이걸 쓸게요"를 선택하지 않아도 바로 브리핑에 쓰이게 하기 위함.
    _activeProvider ??= provider;
    notifyListeners();
    try {
      await _secureStorage.write(key: '$_secureKeyPrefix${provider.name}', value: trimmed);
      if (_activeProvider == provider) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_activeProviderKey, provider.name);
      }
    } catch (e) {
      debugPrint('Error saving AI API key: $e');
    }
  }

  Future<void> removeApiKey(AiProvider provider) async {
    _apiKeys.remove(provider);
    if (_activeProvider == provider) {
      _activeProvider = _apiKeys.keys.isEmpty ? null : _apiKeys.keys.first;
    }
    notifyListeners();
    try {
      await _secureStorage.delete(key: '$_secureKeyPrefix${provider.name}');
      final prefs = await SharedPreferences.getInstance();
      if (_activeProvider == null) {
        await prefs.remove(_activeProviderKey);
      } else {
        await prefs.setString(_activeProviderKey, _activeProvider!.name);
      }
    } catch (e) {
      debugPrint('Error removing AI API key: $e');
    }
  }

  Future<void> setActiveProvider(AiProvider provider) async {
    if (!hasKey(provider)) return;
    _activeProvider = provider;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeProviderKey, provider.name);
    } catch (e) {
      debugPrint('Error saving active AI provider: $e');
    }
  }

  Future<void> setModel(AiProvider provider, String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      _models.remove(provider);
    } else {
      _models[provider] = trimmed;
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (trimmed.isEmpty) {
        await prefs.remove('$_modelPrefix${provider.name}');
      } else {
        await prefs.setString('$_modelPrefix${provider.name}', trimmed);
      }
    } catch (e) {
      debugPrint('Error saving AI model override: $e');
    }
  }
}

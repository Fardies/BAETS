import 'dart:convert';
import 'package:http/http.dart' as http;

class CurrencyService {
  static const String _apiUrl = 'https://api.exchangerate-api.com/v4/latest/USD';

  // In-memory cache — 1 hour
  static Map<String, double>? _cachedRates;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(hours: 1);

  // ── Fetch rates (cached) ──────────────────────────────────────
  static Future<Map<String, double>> getRates() async {
    if (_cachedRates != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedRates!;
    }
    try {
      final response = await http
          .get(Uri.parse(_apiUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rates = Map<String, double>.from(
          (data['rates'] as Map)
              .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        );
        _cachedRates = rates;
        _cacheTime   = DateTime.now();
        return rates;
      }
    } catch (e) {
      print('CurrencyService: using fallback rates. $e');
    }
    return _fallbackRates;
  }

  // ── Synchronous convert (pass cached rates) ───────────────────
  static double convertSync(
      double amount, String from, String to, Map<String, double> rates) {
    if (from == to) return amount;
    final fromRate = rates[from] ?? 1.0;
    final toRate   = rates[to]   ?? 1.0;
    final result   = (amount / fromRate) * toRate;
    return double.parse(result.toStringAsFixed(2));
  }

  // ── Async convert (fetches rates if needed) ───────────────────
  static Future<double> convert({
    required double amount,
    required String from,
    required String to,
  }) async {
    if (from == to) return amount;
    final rates = await getRates();
    return convertSync(amount, from, to, rates);
  }

  // ── Symbol helper ─────────────────────────────────────────────
  static String getSymbol(String code) {
    const symbols = {
      'MYR': 'RM',   'USD': r'$',  'EUR': '€',   'GBP': '£',
      'JPY': '¥',    'AUD': r'A$', 'CAD': r'C$', 'SGD': r'S$',
      'INR': '₹',    'CHF': 'CHF', 'CNY': '¥',   'AED': 'AED',
      'HKD': r'HK$', 'KRW': '₩',  'TRY': '₺',   'BRL': r'R$',
      'AFN': 'Af',   'NOK': 'kr',  'ZAR': 'R',   'NZD': r'NZ$',
      'SEK': 'kr',
    };
    return symbols[code] ?? code;
  }

  // ── Detect currency code from symbol (used by receipt scanner) ─
  static String? detectCurrencyFromSymbol(String symbol) {
    const symbolMap = {
      r'$':  'USD',
      'USD': 'USD',
      '€':   'EUR',
      'EUR': 'EUR',
      '£':   'GBP',
      'GBP': 'GBP',
      '¥':   'JPY',
      'JPY': 'JPY',
      'CNY': 'CNY',
      'RM':  'MYR',
      'MYR': 'MYR',
      r'S$': 'SGD',
      'SGD': 'SGD',
      r'A$': 'AUD',
      'AUD': 'AUD',
      r'C$': 'CAD',
      'CAD': 'CAD',
      '₹':   'INR',
      'INR': 'INR',
      'CHF': 'CHF',
      'AED': 'AED',
      '₩':   'KRW',
      'KRW': 'KRW',
    };
    return symbolMap[symbol.trim()];
  }

  // ── Fallback rates (offline / API down) ───────────────────────
  static const Map<String, double> _fallbackRates = {
    'USD': 1.0,    'MYR': 4.71,  'EUR': 0.92,  'GBP': 0.79,
    'JPY': 149.50, 'AUD': 1.53,  'CAD': 1.36,  'CHF': 0.90,
    'CNY': 7.24,   'INR': 83.12, 'SGD': 1.34,  'AED': 3.67,
    'AFN': 71.0,   'KRW': 1325.0,'HKD': 7.82,  'NOK': 10.55,
    'ZAR': 18.63,  'NZD': 1.63,  'SEK': 10.42, 'BRL': 4.97,
    'TRY': 32.15,
  };
}
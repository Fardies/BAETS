import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'currency_service.dart';

class ReceiptScanResult {
  final double? amount;
  final String? merchantName;
  final String? category;
  final DateTime? date;
  final String? detectedCurrency;   // NEW: currency code found on receipt e.g. 'USD'
  final bool amountExtracted;
  final bool merchantExtracted;
  final bool categoryExtracted;
  final bool dateExtracted;

  ReceiptScanResult({
    this.amount,
    this.merchantName,
    this.category,
    this.date,
    this.detectedCurrency,
    this.amountExtracted = false,
    this.merchantExtracted = false,
    this.categoryExtracted = false,
    this.dateExtracted = false,
  });

  bool get isPartialSuccess => amountExtracted || merchantExtracted || categoryExtracted || dateExtracted;
  bool get isComplete => amountExtracted && merchantExtracted && categoryExtracted && dateExtracted;
  bool get isFailure => !amountExtracted && !merchantExtracted && !categoryExtracted && !dateExtracted;
}

class GeminiReceiptScanner {
  final ImagePicker _picker = ImagePicker();
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  
  // TODO: Replace with your actual API key
  static const String _apiKey = 'AQ.Ab8RN6KAgl3C-B3VW9QDM3CdijQo0-gv31bsiEp23b62sUzr7A';
  
  Future<File?> captureReceipt({ImageSource source = ImageSource.camera}) async {
    try {
      print(source == ImageSource.camera ? '📷 Opening camera...' : '🖼️ Opening gallery...');
      final XFile? photo = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );
      
      if (photo != null) {
        print('✅ Photo captured: ${photo.path}');
        return File(photo.path);
      } else {
        print('❌ User cancelled camera');
        return null;
      }
    } catch (e) {
      print('❌ Error capturing photo: $e');
      return null;
    }
  }
  
  Future<ReceiptScanResult> scanReceipt(File imageFile) async {
    print('🔍 Starting receipt scan...');
    
    try {
      print('📸 Running OCR...');
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final String ocrText = recognizedText.text;
      
      print('✅ OCR completed');
      print('📝 Text length: ${ocrText.length} characters');
      
      if (ocrText.isEmpty) {
        print('⚠️ No text found in image');
        return ReceiptScanResult();
      }
      
      print('=== OCR TEXT ===');
      print(ocrText);
      print('================');
      
      print('🤖 Asking Gemini to extract data...');
      final aiResult = await _extractWithAI(ocrText);
      
      if (aiResult != null) {
        print('✅ AI extraction complete!');
        print('   Merchant: ${aiResult['merchant']}');
        print('   Amount: ${aiResult['amount']}');
        print('   Category: ${aiResult['category']}');
        print('   Date: ${aiResult['date']}');
        
        return ReceiptScanResult(
          merchantName:      aiResult['merchant'],
          amount:            aiResult['amount'],
          category:          aiResult['category'],
          date:              aiResult['date'],
          detectedCurrency:  aiResult['currency'],   // NEW
          merchantExtracted: aiResult['merchant']  != null,
          amountExtracted:   aiResult['amount']    != null,
          categoryExtracted: aiResult['category']  != null,
          dateExtracted:     aiResult['date']      != null,
        );
      } else {
        print('❌ AI extraction failed');
        return ReceiptScanResult();
      }
      
    } catch (e, stackTrace) {
      print('❌ FATAL ERROR: $e');
      print('Stack trace: $stackTrace');
      return ReceiptScanResult();
    }
  }
  
  // Direct HTTP request to Gemini API (with retry logic!)
  Future<Map<String, dynamic>?> _extractWithAI(String ocrText) async {
    const maxRetries = 3;
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final prompt = '''
You are a receipt data extractor. Extract merchant name, total amount, currency, category, and date from the receipt.

OCR Text:
"""
$ocrText
"""

Extract:
1. Merchant Name: Store/company name (usually at top)
2. Total Amount: Final total paid (look for "Total", "Total Sales", "Grand Total", "Amount Due")
   - Do NOT use CASH or CHANGE amounts
   - This is what the customer PAID, not what they gave
3. Currency: Detect the currency used on the receipt
   - Look for symbols: \$ (USD), RM or MYR (Malaysian Ringgit), € (EUR), £ (GBP), ¥ (JPY/CNY), SGD or S\$ (Singapore), AUD or A\$ (Australian), etc.
   - Return the ISO 4217 currency CODE (e.g. "USD", "MYR", "EUR", "GBP", "JPY", "SGD", "AUD")
   - If ¥ symbol is found, determine if it's JPY (Japan) or CNY (China) from context
   - Return null if currency cannot be determined
4. Category: Suggest ONE category from this list based on merchant name:
   - Food & Dining (restaurants, cafes, grocery stores, convenience stores, food courts, bakeries)
   - Transportation (gas stations, petrol stations, parking, toll, ride services, car wash, auto repair)
   - Shopping (retail, clothing, electronics, malls, department stores, general merchandise)
   - Entertainment (movies, cinemas, games, recreation, theme parks, karaoke, sports)
   - Health & Medical (hospitals, clinics, pharmacy, medical centers, dental, veterinary)
   - Bills & Utilities (phone, internet, electricity, water, insurance, banking, government)
   - Education (schools, universities, books, courses, tuition, school supplies, stationery, libraries)
   - Others (if unsure)
5. Receipt Date: Look for date on receipt (common formats: DD-MM-YY, DD/MM/YYYY, etc.)
   - Only extract if clearly visible on receipt
   - Return null if no date found

IMPORTANT:
- Return ONLY valid JSON, no markdown, no explanations
- Use null if field not found or unclear

Return ONLY this exact JSON format:
{
  "merchant": "MERCHANT NAME" or null,
  "amount": 12.34 or null,
  "currency": "MYR" or null,
  "category": "Food & Dining" or null,
  "date": "YYYY-MM-DD" or null
}
''';

        if (attempt > 1) {
          print('🔄 Retry attempt $attempt of $maxRetries...');
          await Future.delayed(Duration(seconds: attempt)); // Wait before retry
        }

        print('📤 Sending HTTP request to Gemini...');
        
        // Direct HTTP POST to Gemini API
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash:generateContent?key=$_apiKey'
        );
        
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'contents': [{
              'parts': [{'text': prompt}]
            }]
          }),
        );
        
        print('📥 Response status: ${response.statusCode}');
        
        // If 503 (busy), retry
        if (response.statusCode == 503 && attempt < maxRetries) {
          print('⚠️ API busy, will retry...');
          continue; // Try again
        }
        
        if (response.statusCode != 200) {
          print('❌ API Error: ${response.body}');
          if (attempt == maxRetries) return null;
          continue;
        }
        
        final jsonResponse = json.decode(response.body);
        final text = jsonResponse['candidates'][0]['content']['parts'][0]['text'];
        
        print('📥 Gemini response:');
        print(text);
        
        // Clean and parse JSON
        String cleanResponse = text.trim();
        if (cleanResponse.startsWith('```json')) {
          cleanResponse = cleanResponse.substring(7);
        }
        if (cleanResponse.startsWith('```')) {
          cleanResponse = cleanResponse.substring(3);
        }
        if (cleanResponse.endsWith('```')) {
          cleanResponse = cleanResponse.substring(0, cleanResponse.length - 3);
        }
        cleanResponse = cleanResponse.trim();
        
        final jsonData = json.decode(cleanResponse);
        
        // Parse date if present
        DateTime? parsedDate;
        if (jsonData['date'] != null && jsonData['date'] is String) {
          try {
            parsedDate = DateTime.parse(jsonData['date']);
            print('📅 Date parsed: $parsedDate');
          } catch (e) {
            print('⚠️ Could not parse date: ${jsonData['date']}');
            parsedDate = null;
          }
        }
        
        return {
          'merchant': jsonData['merchant'] as String?,
          'amount': jsonData['amount'] != null
              ? (jsonData['amount'] is int
                  ? (jsonData['amount'] as int).toDouble()
                  : jsonData['amount'] as double)
              : null,
          'currency': jsonData['currency'] != null
              ? CurrencyService.detectCurrencyFromSymbol(jsonData['currency'] as String)
                ?? jsonData['currency'] as String
              : null,
          'category': jsonData['category'] as String?,
          'date': parsedDate,
        };
        
      } catch (e, stackTrace) {
        print('❌ Error in AI extraction (attempt $attempt): $e');
        if (attempt == maxRetries) {
          print('Stack trace: $stackTrace');
          return null;
        }
      }
    }
    
    return null;
  }
  
  void dispose() {
    try {
      _textRecognizer.close();
      print('✅ Scanner disposed');
    } catch (e) {
      print('❌ Error disposing: $e');
    }
  }
}
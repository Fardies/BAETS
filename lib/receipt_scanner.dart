import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class ReceiptScanResult {
  final double? amount;
  final String? merchantName;
  final bool amountExtracted;
  final bool merchantExtracted;
  
  ReceiptScanResult({
    this.amount,
    this.merchantName,
    this.amountExtracted = false,
    this.merchantExtracted = false,
  });
  
  bool get isPartialSuccess => amountExtracted || merchantExtracted;
  bool get isComplete => amountExtracted && merchantExtracted;
  bool get isFailure => !amountExtracted && !merchantExtracted;
}

class ReceiptScanner {
  final ImagePicker _picker = ImagePicker();
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  
  Future<File?> captureReceipt() async {
    try {
      print('📷 Opening camera...');
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
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
    print('🔍 Starting OCR scan...');
    
    try {
      print('📸 Creating InputImage from file...');
      final inputImage = InputImage.fromFile(imageFile);
      print('✅ InputImage created successfully');
      
      print('🤖 Running text recognition...');
      final recognizedText = await _textRecognizer.processImage(inputImage);
      print('✅ OCR completed');
      
      final String fullText = recognizedText.text;
      print('📝 Text length: ${fullText.length} characters');
      
      if (fullText.isEmpty) {
        print('⚠️ No text found in image');
        return ReceiptScanResult();
      }
      
      print('=== OCR FULL TEXT ===');
      print(fullText);
      print('=====================');
      
      print('💰 Extracting amount...');
      final double? amount = _extractAmount(fullText);
      print(amount != null ? '✅ Amount found: $amount' : '❌ Amount not found');
      
      print('🏪 Extracting merchant...');
      final String? merchant = _extractMerchantName(fullText);
      print(merchant != null ? '✅ Merchant found: $merchant' : '❌ Merchant not found');
      
      return ReceiptScanResult(
        amount: amount,
        merchantName: merchant,
        amountExtracted: amount != null,
        merchantExtracted: merchant != null && merchant.isNotEmpty,
      );
      
    } catch (e, stackTrace) {
      print('❌❌❌ FATAL ERROR in scanReceipt: $e');
      print('Stack trace: $stackTrace');
      return ReceiptScanResult();
    }
  }
  
  // ROBUST amount extraction - stays close to TOTAL keyword, NO fallbacks
  double? _extractAmount(String text) {
    try {
      final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      
      // Find all lines with TOTAL keywords
      for (int i = 0; i < lines.length; i++) {
        final upper = lines[i].toUpperCase();
        
        // Match TOTAL keywords (excluding SUBTOTAL)
        if ((upper.contains('TOTAL SALES') ||
             upper.contains('GRAND TOTAL') ||
             upper.contains('TOTAL AMOUNT') ||
             upper.contains('NET TOTAL') ||
             upper.contains('AMOUNT DUE') ||
             (upper.contains('TOTAL:') && !upper.contains('SUBTOTAL')) ||
             (upper.contains('TOTAL ') && !upper.contains('SUBTOTAL'))) &&
            !upper.contains('SUBTOTAL')) {
          
          print('  Found TOTAL keyword at line $i: "${lines[i]}"');
          
          // Strategy 1: Number on SAME line (best case!)
          final sameLine = _extractNumberFromLine(lines[i]);
          if (sameLine != null && _isValidTotal(sameLine)) {
            print('  ✅ Found on same line: $sameLine');
            return sameLine;
          }
          
          // Strategy 2: Look in NEXT 3 lines ONLY (stay close!)
          for (int j = i + 1; j <= i + 3 && j < lines.length; j++) {
            final line = lines[j];
            final lineUpper = line.toUpperCase();
            
            // STOP if we hit payment keywords
            if (lineUpper.contains('CASH') || lineUpper.contains('CHANGE') ||
                lineUpper.contains('PAYMENT') || lineUpper.contains('BALANCE')) {
              print('  ⚠️ Hit payment keyword at line $j, stopping search');
              break;
            }
            
            // Skip junk
            if (_isJunkLine(line)) continue;
            
            final amount = _extractNumberFromLine(line);
            if (amount != null && _isValidTotal(amount)) {
              print('  ✅ Found close to TOTAL (line $j): $amount');
              return amount;
            }
          }
          
          print('  ⚠️ TOTAL keyword found but no valid amount nearby');
        }
      }
      
      // No confident match found
      print('  ❌ Could not confidently extract total');
      return null;
      
    } catch (e) {
      print('  ❌ Error: $e');
      return null;
    }
  }
  
  // Check if amount is in valid total range (avoids item prices and cash amounts)
  bool _isValidTotal(double amount) {
    return amount >= 1.00 && amount <= 999.99;
  }
  
  // Check if line is junk (dates, codes, item descriptions)
  bool _isJunkLine(String line) {
    // Has hyphen? (dates like 13-08-24, codes like 1004-BANTING)
    if (line.contains('-')) return true;
    
    // Has too many letters? (item descriptions, not amounts)
    final withoutRM = line.replaceAll(RegExp(r'RM|rm', caseSensitive: false), '');
    if (RegExp(r'[a-zA-Z]{3,}').hasMatch(withoutRM)) return true;
    
    return false;
  }
  
  double? _extractNumberFromLine(String line) {
    try {
      // Remove RM prefix
      String cleaned = line.replaceAll(RegExp(r'[RMrm]+'), '');
      cleaned = cleaned.replaceAll(':', '');
      cleaned = cleaned.trim();
      
      // Find decimal numbers
      final regex = RegExp(r'\b(\d{1,3}(?:,\d{3})*\.?\d{0,2})\b');
      final matches = regex.allMatches(cleaned);
      
      for (var match in matches) {
        final numStr = match.group(0);
        if (numStr != null && numStr.isNotEmpty) {
          try {
            final cleanNum = numStr.replaceAll(',', '');
            final amount = double.parse(cleanNum);
            if (amount >= 0.01 && amount <= 99999) {
              return amount;
            }
          } catch (e) {
            continue;
          }
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
  
  String? _extractMerchantName(String text) {
    try {
      final lines = text.split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      
      if (lines.isEmpty) return null;
      
      print('=== ANALYZING LINES FOR MERCHANT ===');
      
      for (int i = 0; i < 5 && i < lines.length; i++) {
        final line = lines[i];
        print('  Line $i: "$line"');
        
        if (line.length < 3) {
          print('    -> Too short');
          continue;
        }
        
        // Skip time format
        if (RegExp(r'^\d{1,2}:\d{2}(AM|PM|am|pm)?$').hasMatch(line)) {
          print('    -> Time format');
          continue;
        }
        
        // Skip pure numbers
        if (RegExp(r'^[\d\s\-\.\,\:]+$').hasMatch(line)) {
          print('    -> Only numbers/symbols');
          continue;
        }
        
        // Skip postcodes (unless contains SDN)
        if (RegExp(r'\d{5}').hasMatch(line) && !line.toUpperCase().contains('SDN')) {
          print('    -> Postcode');
          continue;
        }
        
        // Skip phone numbers
        if (line.toLowerCase().startsWith('tel:') || 
            line.toLowerCase().startsWith('phone:') ||
            line.toLowerCase().startsWith('hp:')) {
          print('    -> Phone number');
          continue;
        }
        
        // Skip common headers
        final lowerLine = line.toLowerCase();
        if (lowerLine.contains('welcome') ||
            lowerLine.contains('terima kasih') ||
            lowerLine.contains('thank you') ||
            lowerLine == 'receipt' ||
            lowerLine == 'invoice' ||
            lowerLine.contains('tax invoice')) {
          print('    -> Common header');
          continue;
        }
        
        // Must have letters
        final hasLetters = RegExp(r'[a-zA-Z]').hasMatch(line);
        if (hasLetters && line.length >= 4) {
          print('    -> ✅ FOUND MERCHANT');
          return _cleanMerchantName(line);
        }
      }
      
      // Fallback: first line with letters
      for (String line in lines.take(3)) {
        if (RegExp(r'[a-zA-Z]').hasMatch(line) && line.length >= 3) {
          print('  Fallback merchant: "$line"');
          return _cleanMerchantName(line);
        }
      }
      
      print('  No merchant found');
      return null;
      
    } catch (e) {
      print('  Error in _extractMerchantName: $e');
      return null;
    }
  }
  
  String _cleanMerchantName(String name) {
    try {
      String cleaned = name.trim().replaceAll(RegExp(r'\s+'), ' ');
      cleaned = cleaned.replaceAll(RegExp(r'\s+(SDN\s+BHD\.?)$', caseSensitive: false), ' SDN. BHD.');
      cleaned = cleaned.replaceAll(RegExp(r'\s+(PTE\s+LTD\.?)$', caseSensitive: false), ' PTE. LTD.');
      return cleaned.trim();
    } catch (e) {
      return name;
    }
  }
  
  void dispose() {
    try {
      _textRecognizer.close();
      print('✅ TextRecognizer disposed');
    } catch (e) {
      print('❌ Error disposing TextRecognizer: $e');
    }
  }
}


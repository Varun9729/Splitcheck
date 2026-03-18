import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class ReceiptAiService {

  Future<Map<String, dynamic>> parseReceipt(String imageUrl) async {
    try {
      debugPrint('Calling parseReceiptWithAi...');
      debugPrint('imageUrl: $imageUrl');

      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('parseReceiptWithAi');

      final result = await callable.call({'imageUrl': imageUrl});

      debugPrint('Function result: ${result.data}');
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e, st) {
      debugPrint('=== FirebaseFunctionsException ===');
      debugPrint('code: ${e.code}');
      debugPrint('message: ${e.message}');
      debugPrint('details: ${e.details}');
      debugPrintStack(stackTrace: st);
      rethrow;
    } catch (e, st) {
      debugPrint('=== Unknown parseReceipt error ===');
      debugPrint('$e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }
}

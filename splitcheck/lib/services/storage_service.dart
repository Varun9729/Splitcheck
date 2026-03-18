import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class StorageService {
  final FirebaseStorage storage = FirebaseStorage.instanceFor(
    bucket: 'gs://splitcheck-9f211.firebasestorage.app',
  );

  Future<String> uploadReceiptImage({
    required dynamic file,
    required String slug,
    Uint8List? bytes,
  }) async {
    try {
      debugPrint('Starting upload for slug: $slug');

      final ref = storage.ref().child('receipts/$slug.jpg');
      debugPrint('Uploading to: ${ref.fullPath}');

      TaskSnapshot snapshot;
      if (kIsWeb) {
        // Web: use putData with bytes
        if (bytes == null) {
          throw Exception('bytes required for web upload');
        }
        snapshot = await ref.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
      } else {
        // Mobile: use putFile
        snapshot = await ref.putFile(file as File);
      }

      debugPrint('Upload complete. State: ${snapshot.state}');

      final downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('Download URL: $downloadUrl');

      return downloadUrl;
    } catch (e, st) {
      debugPrint('Storage upload failed: $e');
      debugPrint('$st');
      rethrow;
    }
  }
}

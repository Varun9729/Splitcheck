import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

//Vision Service
class VisionService {
  final String apiKey; // Extracted from your JSON for testing

  VisionService(this.apiKey);

  Future<String> extractTextFromImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final url = 'https://vision.googleapis.com/v1/images:annotate?key=$apiKey';

    final payload = {
      "requests": [
        {
          "image": {"content": base64Image},
          "features": [
            {"type": "TEXT_DETECTION"},
          ],
        },
      ],
    };

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('Vision API error: ${response.body}');
    }

    final jsonResponse = jsonDecode(response.body);
    final text = jsonResponse['responses'][0]['fullTextAnnotation']?['text'];
    return text ?? '';
  }
}

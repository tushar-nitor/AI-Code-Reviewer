import 'dart:convert';
import 'dart:io';
import 'package:ai_code_reviewer/common/methods.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb

class DocumentService {
  static Future<Map<String, dynamic>> uploadDocument() async {
    final uri = Uri.https(baseUrl, 'ingestDocument');

    try {
      // 1. Pick file
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'txt'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        // 2. Handle file data differently for web vs mobile
        String base64File;
        final String fileName = file.name;
        final String mimeType = file.extension == 'pdf'
            ? 'application/pdf'
            : file.extension == 'docx'
            ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
            : 'text/plain';

        if (kIsWeb) {
          // Web platform
          base64File = base64Encode(file.bytes!);
        } else {
          // Mobile/Desktop platform
          final ioFile = File(file.path!);
          final fileBytes = await ioFile.readAsBytes();
          base64File = base64Encode(fileBytes);
        }

        // 3. Call your Genkit endpoint
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            "data": {
              'fileName': fileName,
              'mimeType': mimeType,
              'fileData': base64File,
              'namespace': 'flutter_uploads',
            },
          }),
        );

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else {
          throw Exception('Server error: ${response.statusCode}');
        }
      }
      throw Exception('No file selected');
    } catch (e) {
      debugPrint('Upload error: $e');
      rethrow;
    }
  }
}

import 'dart:typed_data';

class Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final Uint8List? fileBytes;
  final String? fileMimeType;
  final String? fileName;

  Message({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.fileBytes,
    this.fileMimeType,
    this.fileName,
  });
}

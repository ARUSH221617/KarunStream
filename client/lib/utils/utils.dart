import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../features/common/remote/api_client.dart';
import '../generated/locale_keys.g.dart';

class Utils {
  Utils._();

  static Future<bool> haveConnection() async {
    final connectivityResults = await Connectivity().checkConnectivity();
    return !connectivityResults.contains(ConnectivityResult.none);
  }

  static String getErrorMessage(Object? error) {
    if (error is TimeoutException) return error.message;
    if (error is NoInternetException) return error.message;
    if (error is RequestCancelledException) return error.message;
    if (error is BadRequestException) return error.message;
    if (error is UnauthorizedException) return error.message;
    if (error is ForbiddenException) return error.message;
    if (error is NotFoundException) return error.message;
    if (error is ServerException) return error.message;
    if (error is UnknownException) return error.message;
    return LocaleKeys.unexpectedErrorOccurred.tr();
  }

  static DateTime today() {
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day);
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(1)} B/s';
    }
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    if (bytesPerSecond < 1024 * 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
  }

  static IconData getFileIcon(String filename) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      // Archives
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
      case '.bz2':
      case '.xz':
        return Icons.folder_zip_outlined;
      // Images
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.bmp':
      case '.webp':
      case '.svg':
      case '.heic':
        return Icons.image_outlined;
      // Video
      case '.mp4':
      case '.avi':
      case '.mkv':
      case '.mov':
      case '.flv':
      case '.webm':
      case '.3gp':
      case '.mpeg':
        return Icons.video_file_outlined;
      // Audio
      case '.mp3':
      case '.wav':
      case '.flac':
      case '.ogg':
      case '.m4a':
      case '.wma':
      case '.aac':
        return Icons.audio_file_outlined;
      // Documents
      case '.pdf':
        return Icons.picture_as_pdf_outlined;
      case '.doc':
      case '.docx':
      case '.odt':
      case '.rtf':
        return Icons.description_outlined;
      // Spreadsheets
      case '.xls':
      case '.xlsx':
      case '.ods':
      case '.csv':
        return Icons.table_chart_outlined;
      // Presentations
      case '.ppt':
      case '.pptx':
      case '.odp':
        return Icons.slideshow_outlined;
      // Code / Text
      case '.html':
      case '.css':
      case '.js':
      case '.ts':
      case '.jsx':
      case '.tsx':
      case '.py':
      case '.dart':
      case '.go':
      case '.java':
      case '.cpp':
      case '.c':
      case '.h':
      case '.cs':
      case '.sh':
      case '.bat':
      case '.json':
      case '.xml':
      case '.yaml':
      case '.yml':
        return Icons.code_outlined;
      case '.txt':
      case '.md':
      case '.log':
        return Icons.text_snippet_outlined;
      // Executables / Installers
      case '.apk':
      case '.exe':
      case '.msi':
      case '.dmg':
      case '.pkg':
      case '.deb':
      case '.rpm':
        return Icons.install_mobile_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  static Color getFileColor(String filename) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
      case '.bz2':
      case '.xz':
        return const Color(0xFFFF9100); // Amber/orange for archives
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.bmp':
      case '.webp':
      case '.svg':
      case '.heic':
        return const Color(0xFF4CAF50); // Green for images
      case '.mp4':
      case '.avi':
      case '.mkv':
      case '.mov':
      case '.flv':
      case '.webm':
      case '.3gp':
      case '.mpeg':
        return const Color(0xFFE91E63); // Pink/Red for videos
      case '.mp3':
      case '.wav':
      case '.flac':
      case '.ogg':
      case '.m4a':
      case '.wma':
      case '.aac':
        return const Color(0xFF9C27B0); // Purple for audio
      case '.pdf':
        return const Color(0xFFF44336); // Red for PDF
      case '.doc':
      case '.docx':
      case '.odt':
      case '.rtf':
        return const Color(0xFF2196F3); // Blue for Word doc
      case '.xls':
      case '.xlsx':
      case '.ods':
      case '.csv':
        return const Color(0xFF009688); // Teal for spreadsheets
      case '.ppt':
      case '.pptx':
      case '.odp':
        return const Color(0xFFFF5722); // Deep orange for presentations
      case '.html':
      case '.css':
      case '.js':
      case '.ts':
      case '.jsx':
      case '.tsx':
      case '.py':
      case '.dart':
      case '.go':
      case '.java':
      case '.cpp':
      case '.c':
      case '.h':
      case '.cs':
      case '.sh':
      case '.bat':
      case '.json':
      case '.xml':
      case '.yaml':
      case '.yml':
        return const Color(0xFF00BCD4); // Cyan for code
      case '.txt':
      case '.md':
      case '.log':
        return const Color(0xFF757575); // Grey for text
      case '.apk':
      case '.exe':
      case '.msi':
      case '.dmg':
      case '.pkg':
      case '.deb':
      case '.rpm':
        return const Color(0xFF607D8B); // Blue-grey for apps
      default:
        return const Color(0xFF78909C); // Cool grey for default
    }
  }
}

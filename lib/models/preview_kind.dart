import 'storage_file.dart';

/// Как показывать файл в предпросмотре.
enum PreviewKind { image, svg, video, audio, pdf, archive, text, none }

const _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'wbmp'};
const _videoExt = {'mp4', 'm4v', 'mov', 'webm', 'mkv', '3gp', 'ts'};
const _audioExt = {'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'oga', 'opus', 'amr'};
const _textExt = {
  'txt', 'md', 'markdown', 'log', 'json', 'jsonl', 'xml', 'yaml', 'yml', 'toml',
  'ini', 'cfg', 'conf', 'csv', 'tsv', 'html', 'htm', 'css', 'scss', 'js', 'mjs',
  'ts', 'tsx', 'jsx', 'dart', 'py', 'kt', 'kts', 'java', 'c', 'h', 'cpp', 'hpp',
  'cs', 'go', 'rs', 'rb', 'php', 'sh', 'bash', 'zsh', 'ps1', 'bat', 'cmd', 'sql',
  'gradle', 'properties', 'env', 'lua', 'swift', 'vue', 'svelte', 'tex', 'srt',
  'vtt', 'nfo', 'diff', 'patch', 'lock', 'gitignore', 'rst', 'svg',
};

String fileExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

PreviewKind previewKindOf(StorageFile file) {
  final ext = fileExtension(file.name);
  final mime = file.mime.toLowerCase();

  if (ext == 'svg' || mime == 'image/svg+xml') return PreviewKind.svg;

  final unsupportedImage = mime.contains('heic') ||
      mime.contains('heif') ||
      mime.contains('tiff') ||
      mime.contains('avif');
  if (_imageExt.contains(ext) ||
      (mime.startsWith('image/') && !unsupportedImage) ||
      (file.kind == 'image' && ext.isEmpty && !unsupportedImage)) {
    return PreviewKind.image;
  }

  if (_videoExt.contains(ext) || mime.startsWith('video/') || file.kind == 'video') {
    return PreviewKind.video;
  }
  if (_audioExt.contains(ext) || mime.startsWith('audio/') || file.kind == 'audio') {
    return PreviewKind.audio;
  }
  if (ext == 'pdf' || mime == 'application/pdf' || file.kind == 'pdf') {
    return PreviewKind.pdf;
  }

  final zipMime = mime == 'application/zip' ||
      mime == 'application/x-zip-compressed' ||
      mime == 'application/java-archive' ||
      mime == 'application/vnd.android.package-archive';
  if (ext == 'zip' || ext == 'jar' || ext == 'apk' || zipMime) {
    return PreviewKind.archive;
  }

  final textMime = mime.startsWith('text/') ||
      mime == 'application/json' ||
      mime == 'application/xml' ||
      mime == 'application/javascript' ||
      mime == 'application/x-yaml' ||
      mime == 'application/x-sh';
  if (_textExt.contains(ext) || textMime || file.kind == 'text' || file.kind == 'code') {
    return PreviewKind.text;
  }
  return PreviewKind.none;
}

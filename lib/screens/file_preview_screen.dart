import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../format.dart';
import '../icons.dart';
import '../models/preview_kind.dart';
import '../models/storage_file.dart';
import '../providers/app_provider.dart';
import '../providers/storage_provider.dart';
import '../services/api_client.dart';
import '../services/preview_service.dart';
import '../services/zip_reader.dart';
import '../theme.dart';

String _errorText(Object error) {
  if (error is PreviewException) return error.message;
  if (error is ApiException) return error.message;
  if (error is PlatformException) {
    if (error.code == 'password') {
      return 'PDF защищён паролем, откройте его после скачивания';
    }
    return 'Не удалось показать PDF';
  }
  return 'Не удалось загрузить файл';
}

/// Ширина декодирования картинок. Одна и та же для показа и для предзагрузки,
/// чтобы предзагруженная картинка попадала в кэш Flutter.
const _imageCacheWidth = 2400;

const _proseExt = {'txt', 'md', 'markdown', 'log', 'csv', 'tsv', 'nfo', 'rst', 'srt', 'vtt'};

bool _isCode(StorageFile file) =>
    file.kind == 'code' || !_proseExt.contains(fileExtension(file.name));

/// Предпросмотр файлов хранилища: изображения, видео, аудио, PDF, текст и код.
/// Между файлами можно листать свайпом влево и вправо.
class FilePreviewScreen extends StatefulWidget {
  const FilePreviewScreen({
    super.key,
    required this.provider,
    required this.files,
    required this.initialIndex,
  });

  final StorageProvider provider;
  final List<StorageFile> files;
  final int initialIndex;

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  late final PageController _pages;
  late int _index;

  /// Пока изображение увеличено, свайп должен двигать картинку, а не листать.
  bool _zoomed = false;

  StorageProvider get _provider => widget.provider;
  StorageFile get _file => widget.files[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.files.length - 1);
    _pages = PageController(initialPage: _index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheNeighbors());
  }

  /// Заранее подгружает соседние изображения, чтобы при листании они
  /// появлялись сразу.
  Future<void> _precacheNeighbors() async {
    for (final i in [_index + 1, _index - 1]) {
      if (i < 0 || i >= widget.files.length) continue;
      final file = widget.files[i];
      if (previewKindOf(file) != PreviewKind.image) continue;
      try {
        final headers = await _provider.previewHeaders();
        if (!mounted) return;
        final url = _provider.fileUri(file, download: false).toString();
        await precacheImage(
          ResizeImage(NetworkImage(url, headers: headers), width: _imageCacheWidth),
          context,
          onError: (error, stack) {},
        );
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _download(StorageFile file) {
    unawaited(_provider.download(file));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Скачивание началось')));
  }

  void _setZoomed(int pageIndex, bool zoomed) {
    if (!mounted || pageIndex != _index || zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
  }

  Widget _page(int index) {
    final file = widget.files[index];
    final Widget body;
    switch (previewKindOf(file)) {
      case PreviewKind.image:
        body = _ImagePreview(
          provider: _provider,
          file: file,
          onZoomChanged: (z) => _setZoomed(index, z),
        );
      case PreviewKind.svg:
        body = _SvgPreview(
          provider: _provider,
          file: file,
          onZoomChanged: (z) => _setZoomed(index, z),
        );
      case PreviewKind.video:
        body = _MediaPreview(provider: _provider, file: file, audio: false);
      case PreviewKind.audio:
        body = _MediaPreview(provider: _provider, file: file, audio: true);
      case PreviewKind.pdf:
        body = _PdfPreview(provider: _provider, file: file);
      case PreviewKind.archive:
        body = _ArchivePreview(provider: _provider, file: file);
      case PreviewKind.text:
        body = _TextPreview(provider: _provider, file: file, code: _isCode(file));
      case PreviewKind.none:
        body = _Unsupported(onDownload: () => _download(file));
    }
    return KeyedSubtree(key: ValueKey(file.name), child: body);
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final total = widget.files.length;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(file.name, overflow: TextOverflow.ellipsis),
            if (total > 1)
              Text(
                '${_index + 1} из $total',
                style: const TextStyle(color: TmpsColors.muted, fontSize: 12),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const TmpsIcon(Ico.download, size: 21),
            tooltip: 'Скачать',
            onPressed: () => _download(file),
          ),
          IconButton(
            icon: const TmpsIcon(Ico.share, size: 21),
            tooltip: 'Поделиться ссылкой',
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: _provider.fileUri(file).toString()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
              itemCount: total,
              onPageChanged: (i) {
                setState(() {
                  _index = i;
                  _zoomed = false;
                });
                unawaited(_precacheNeighbors());
              },
              itemBuilder: (context, i) => _page(i),
            ),
          ),
          Container(
            width: double.infinity,
            color: TmpsColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SafeArea(
              top: false,
              child: Text(
                '${fmtSize(file.size)} · ${file.mime}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: TmpsColors.muted, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Масштабирование щипком и двойным тапом. Сообщает наружу, увеличено ли
/// сейчас содержимое, чтобы экран мог отключить листание.
class _ZoomView extends StatefulWidget {
  const _ZoomView({required this.child, this.onZoomChanged});

  final Widget child;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<_ZoomView> createState() => _ZoomViewState();
}

class _ZoomViewState extends State<_ZoomView> {
  final TransformationController _controller = TransformationController();
  bool _zoomed = false;
  Offset _tap = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _controller.dispose();
    super.dispose();
  }

  void _onChange() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
  }

  void _toggle() {
    if (_zoomed) {
      _controller.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    _controller.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, -_tap.dx * (scale - 1))
      ..setEntry(1, 3, -_tap.dy * (scale - 1));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _tap = details.localPosition,
      onDoubleTap: _toggle,
      child: SizedBox.expand(
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 1,
          maxScale: 6,
          child: widget.child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Общие виджеты

class _Loading extends StatelessWidget {
  const _Loading({this.progress, this.label});

  final double? progress;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final value = progress != null && progress! > 0 && progress! < 1 ? progress : null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(value: value, color: TmpsColors.accent),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: const TextStyle(color: TmpsColors.muted, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TmpsIcon(Ico.alert, size: 34, color: TmpsColors.danger),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: TmpsColors.muted, height: 1.4),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const TmpsIcon(Ico.refresh, size: 18),
                label: const Text('Повторить'),
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Unsupported extends StatelessWidget {
  const _Unsupported({required this.onDownload});

  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TmpsIcon(Ico.file, size: 44, color: TmpsColors.faint),
            const SizedBox(height: 14),
            const Text(
              'Предпросмотр для этого типа файлов недоступен',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              'Скачайте файл и откройте его в подходящем приложении.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TmpsColors.muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: const TmpsIcon(Ico.download, size: 18, color: Colors.white),
              label: const Text('Скачать'),
              onPressed: onDownload,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Изображения

class _ImagePreview extends StatefulWidget {
  const _ImagePreview({required this.provider, required this.file, this.onZoomChanged});

  final StorageProvider provider;
  final StorageFile file;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  late Future<Map<String, String>> _headers;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _headers = widget.provider.previewHeaders();
  }

  void _retry() {
    setState(() {
      _attempt++;
      _headers = widget.provider.previewHeaders(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _headers,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _PreviewError(message: _errorText(snapshot.error!), onRetry: _retry);
        }
        final headers = snapshot.data;
        if (headers == null) return const _Loading();
        final url = widget.provider.fileUri(widget.file, download: false).toString();
        return _ZoomView(
          onZoomChanged: widget.onZoomChanged,
          child: Center(
            child: Image.network(
              url,
              key: ValueKey(_attempt),
              headers: headers,
              fit: BoxFit.contain,
              cacheWidth: _imageCacheWidth,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                final total = progress.expectedTotalBytes;
                return _Loading(
                  progress: total == null ? null : progress.cumulativeBytesLoaded / total,
                );
              },
              errorBuilder: (context, error, stack) => _PreviewError(
                message: 'Не удалось показать изображение. '
                    'Формат может не поддерживаться, скачайте файл.',
                onRetry: _retry,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SvgPreview extends StatefulWidget {
  const _SvgPreview({required this.provider, required this.file, this.onZoomChanged});

  final StorageProvider provider;
  final StorageFile file;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<_SvgPreview> createState() => _SvgPreviewState();
}

class _SvgPreviewState extends State<_SvgPreview> {
  static const _limit = 5 * 1024 * 1024;
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    try {
      final headers = await widget.provider.previewHeaders(refresh: refresh);
      final bytes = await PreviewLoader.loadBytes(
        widget.provider.fileUri(widget.file, download: false),
        headers,
        maxBytes: _limit,
        allowTruncate: false,
        knownSize: widget.file.size,
      );
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return _PreviewError(
        message: error,
        onRetry: () {
          setState(() => _error = null);
          _load(refresh: true);
        },
      );
    }
    final bytes = _bytes;
    if (bytes == null) return const _Loading();
    return _ZoomView(
      onZoomChanged: widget.onZoomChanged,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SvgPicture.memory(bytes, fit: BoxFit.contain),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Текст и код

class _TextPreview extends StatefulWidget {
  const _TextPreview({required this.provider, required this.file, required this.code});

  final StorageProvider provider;
  final StorageFile file;
  final bool code;

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  static const _limit = 200 * 1024;

  List<String>? _lines;
  bool _truncated = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    try {
      if (widget.file.size == 0) {
        if (!mounted) return;
        setState(() {
          _lines = const [];
          _truncated = false;
        });
        return;
      }
      final headers = await widget.provider.previewHeaders(refresh: refresh);
      final bytes = await PreviewLoader.loadBytes(
        widget.provider.fileUri(widget.file, download: false),
        headers,
        maxBytes: _limit,
        allowTruncate: true,
        knownSize: widget.file.size,
      );
      final probe = bytes.length < 8192 ? bytes.length : 8192;
      for (var i = 0; i < probe; i++) {
        if (bytes[i] == 0) {
          throw PreviewException('Файл похож на двоичный, предпросмотр недоступен');
        }
      }
      var text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      final lines = text.split(RegExp(r'\r\n|\r|\n'));
      if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _truncated = widget.file.size > bytes.length;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return _PreviewError(
        message: error,
        onRetry: () {
          setState(() => _error = null);
          _load(refresh: true);
        },
      );
    }
    final lines = _lines;
    if (lines == null) return const _Loading();
    if (lines.isEmpty) {
      return const Center(
        child: Text('Файл пустой', style: TextStyle(color: TmpsColors.muted)),
      );
    }

    const mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.45,
      color: TmpsColors.text,
    );
    final gutter = lines.length.toString().length * 8.0 + 6;
    final extra = _truncated ? 1 : 0;

    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: lines.length + extra,
        itemBuilder: (context, index) {
          if (index == lines.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                'Показаны первые ${fmtSize(_limit)} из ${fmtSize(widget.file.size)}. '
                'Скачайте файл, чтобы прочитать его целиком.',
                style: const TextStyle(color: TmpsColors.warn, fontSize: 12.5, height: 1.4),
              ),
            );
          }
          final line = lines[index];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.code) ...[
                SizedBox(
                  width: gutter,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.right,
                    style: mono.copyWith(color: TmpsColors.faint),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(child: Text(line.isEmpty ? ' ' : line, style: mono)),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PDF

class _PdfPreview extends StatefulWidget {
  const _PdfPreview({required this.provider, required this.file});

  final StorageProvider provider;
  final StorageFile file;

  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  static const _limit = 60 * 1024 * 1024;
  static const _zooms = [1.0, 1.5, 2.0, 3.0];
  static const _cacheSize = 14;

  File? _file;
  int _pages = 0;
  double _progress = 0;
  bool _ready = false;
  String? _error;
  int _zoomIndex = 0;
  final Map<String, Future<Uint8List>> _cache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    unawaited(PdfRendererService.close());
    try {
      _file?.deleteSync();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    try {
      final headers = await widget.provider.previewHeaders(refresh: refresh);
      final dir = await getTemporaryDirectory();
      final target = File('${dir.path}/preview/${DateTime.now().microsecondsSinceEpoch}.pdf');
      _file = target;
      await PreviewLoader.loadToFile(
        widget.provider.fileUri(widget.file, download: false),
        headers,
        target,
        maxBytes: _limit,
        knownSize: widget.file.size,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      final pages = await PdfRendererService.open(target.path);
      if (!mounted) return;
      if (pages <= 0) throw PreviewException('В этом PDF нет страниц');
      setState(() {
        _pages = pages;
        _ready = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(e));
    }
  }

  Future<Uint8List> _render(int index, int width) {
    final key = '$index@$width';
    final future = _cache.remove(key) ?? PdfRendererService.render(index, width);
    _cache[key] = future;
    future.then((_) {}, onError: (Object _) {
      _cache.remove(key);
    });
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  void _zoom(int delta) {
    setState(() {
      _zoomIndex = (_zoomIndex + delta).clamp(0, _zooms.length - 1);
      _cache.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return _PreviewError(
        message: error,
        onRetry: () {
          setState(() {
            _error = null;
            _progress = 0;
          });
          _load(refresh: true);
        },
      );
    }
    if (!_ready) return _Loading(progress: _progress, label: 'Загружаю PDF…');

    final zoom = _zooms[_zoomIndex];
    return LayoutBuilder(
      builder: (context, box) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final pageWidth = box.maxWidth * zoom;
        final pixels = (pageWidth * dpr).round().clamp(400, 2600);
        final list = ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _pages,
          itemBuilder: (context, index) => _PdfPage(
            key: ValueKey('$index@$pixels'),
            future: _render(index, pixels),
            width: pageWidth,
          ),
        );
        return Column(
          children: [
            Expanded(
              child: zoom > 1
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: pageWidth, child: list),
                    )
                  : list,
            ),
            Container(
              color: TmpsColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    '$_pages ${plural(_pages, 'страница', 'страницы', 'страниц')}',
                    style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const TmpsIcon(Ico.minus, size: 20),
                    tooltip: 'Уменьшить',
                    onPressed: _zoomIndex > 0 ? () => _zoom(-1) : null,
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${(zoom * 100).round()} %',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const TmpsIcon(Ico.plus, size: 20),
                    tooltip: 'Увеличить',
                    onPressed: _zoomIndex < _zooms.length - 1 ? () => _zoom(1) : null,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PdfPage extends StatelessWidget {
  const _PdfPage({super.key, required this.future, required this.width});

  final Future<Uint8List> future;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FutureBuilder<Uint8List>(
        future: future,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null) {
            return Image.memory(
              bytes,
              width: width,
              fit: BoxFit.fitWidth,
              gaplessPlayback: true,
            );
          }
          return Container(
            width: width,
            height: width * 1.35,
            color: Colors.white,
            alignment: Alignment.center,
            child: snapshot.hasError
                ? const Text(
                    'Не удалось показать страницу',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  )
                : const CircularProgressIndicator(color: TmpsColors.accent),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Архивы

class _ArchivePreview extends StatefulWidget {
  const _ArchivePreview({required this.provider, required this.file});

  final StorageProvider provider;
  final StorageFile file;

  @override
  State<_ArchivePreview> createState() => _ArchivePreviewState();
}

class _ArchivePreviewState extends State<_ArchivePreview> {
  ZipListing? _listing;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    try {
      final headers = await widget.provider.previewHeaders(refresh: refresh);
      final listing = await ZipReader.list(
        widget.provider.fileUri(widget.file, download: false),
        headers,
        widget.file.size,
      );
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return _PreviewError(
        message: error,
        onRetry: () {
          setState(() => _error = null);
          _load(refresh: true);
        },
      );
    }
    final listing = _listing;
    if (listing == null) return const _Loading(label: 'Читаю оглавление…');
    if (listing.entries.isEmpty) {
      return const Center(
        child: Text('Архив пустой', style: TextStyle(color: TmpsColors.muted)),
      );
    }

    final files = listing.fileCount;
    final folders = listing.directoryCount;
    final summary = StringBuffer('$files ${plural(files, 'файл', 'файла', 'файлов')}');
    if (folders > 0) {
      summary.write(' · $folders ${plural(folders, 'папка', 'папки', 'папок')}');
    }
    summary.write(' · ${fmtSize(listing.unpackedSize)} после распаковки');

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: TmpsColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            summary.toString(),
            style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: listing.entries.length + (listing.truncated ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == listing.entries.length) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Показаны первые ${listing.entries.length} из ${listing.total} записей.',
                    style: const TextStyle(color: TmpsColors.warn, fontSize: 12.5),
                  ),
                );
              }
              final entry = listing.entries[index];
              final indent = 14.0 + (entry.depth > 6 ? 6 : entry.depth) * 14.0;
              return Padding(
                padding: EdgeInsets.fromLTRB(indent, 7, 16, 7),
                child: Row(
                  children: [
                    TmpsIcon(
                      entry.isDirectory ? Ico.folder : (entry.encrypted ? Ico.lock : Ico.file),
                      size: 18,
                      color: entry.isDirectory ? TmpsColors.accent : TmpsColors.muted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.baseName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ),
                    if (!entry.isDirectory) ...[
                      const SizedBox(width: 10),
                      Text(
                        fmtSize(entry.size),
                        style: const TextStyle(color: TmpsColors.faint, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Видео и аудио

class _MediaPreview extends StatefulWidget {
  const _MediaPreview({required this.provider, required this.file, required this.audio});

  final StorageProvider provider;
  final StorageFile file;
  final bool audio;

  @override
  State<_MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<_MediaPreview> {
  late final AppProvider _app;
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Пока открыт плеер, автоблокировка по таймеру не срабатывает.
    _app = context.read<AppProvider>()..holdLock();
    _init();
  }

  @override
  void dispose() {
    _app.releaseLock();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init({bool refresh = false}) async {
    VideoPlayerController? controller;
    try {
      final headers = await widget.provider.previewHeaders(refresh: refresh);
      controller = VideoPlayerController.networkUrl(
        widget.provider.fileUri(widget.file, download: false),
        httpHeaders: headers,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
      unawaited(controller.play());
    } catch (e) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.message
            : 'Не удалось воспроизвести файл. Формат может не поддерживаться, скачайте его.';
      });
    }
  }

  void _retry() {
    final old = _controller;
    setState(() {
      _controller = null;
      _error = null;
    });
    old?.dispose();
    _init(refresh: true);
  }

  Future<void> _toggle(VideoPlayerController c) async {
    final v = c.value;
    if (v.isPlaying) {
      await c.pause();
      return;
    }
    if (v.duration > Duration.zero && v.position >= v.duration) {
      await c.seekTo(Duration.zero);
    }
    await c.play();
  }

  String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) return _PreviewError(message: error, onRetry: _retry);
    final controller = _controller;
    if (controller == null) return const _Loading();

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggle(controller),
            child: Center(
              child: widget.audio
                  ? _AudioCover(name: widget.file.name)
                  : AspectRatio(
                      aspectRatio:
                          controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9,
                      child: VideoPlayer(controller),
                    ),
            ),
          ),
        ),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final total = value.duration.inMilliseconds;
            final position = value.position.inMilliseconds.clamp(0, total > 0 ? total : 0);
            return Container(
              color: TmpsColors.surface,
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value.hasError)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Ошибка воспроизведения. Попробуйте скачать файл.',
                        style: TextStyle(color: TmpsColors.danger, fontSize: 12.5),
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        icon: TmpsIcon(value.isPlaying ? Ico.pause : Ico.play, size: 26),
                        tooltip: value.isPlaying ? 'Пауза' : 'Играть',
                        onPressed: () => _toggle(controller),
                      ),
                      Text(
                        _clock(value.position),
                        style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5),
                      ),
                      Expanded(
                        child: Slider(
                          value: position.toDouble(),
                          min: 0,
                          max: total > 0 ? total.toDouble() : 1,
                          onChanged: total > 0
                              ? (x) => controller.seekTo(Duration(milliseconds: x.round()))
                              : null,
                        ),
                      ),
                      Text(
                        _clock(value.duration),
                        style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5),
                      ),
                      if (value.isBuffering) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: TmpsColors.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AudioCover extends StatelessWidget {
  const _AudioCover({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: TmpsColors.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: TmpsColors.border),
            ),
            child: const TmpsIcon(Ico.audio, size: 48, color: Color(0xFFFBBF24)),
          ),
          const SizedBox(height: 18),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

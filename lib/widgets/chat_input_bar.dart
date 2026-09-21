import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_message.dart';
import '../services/file_attachment_service.dart';
import '../theme/app_theme.dart';

/// Cap on video size — base64 inflates this by ~33%, and a large video
/// turns into a huge, expensive request even though the transport itself
/// is local. 15MB keeps things reasonable for a short clip.
const int _maxVideoBytes = 15 * 1024 * 1024;

class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool isSending;
  final void Function(
    String text,
    List<ImageAttachment> images,
    List<VideoAttachment> videos,
    List<TextFileAttachment> textFiles,
  ) onSend;
  final VoidCallback onStop;
  final String? editingBannerText;
  final VoidCallback? onCancelEdit;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.onStop,
    this.editingBannerText,
    this.onCancelEdit,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _picker = ImagePicker();
  bool _hasText = false;
  final List<_PendingImage> _pendingImages = [];
  final List<_PendingVideo> _pendingVideos = [];
  final List<ExtractedTextFile> _pendingTextFiles = [];

  TextEditingController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _hasText = _controller.text.trim().isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    // Not disposing _controller here — it's owned by the parent (HomeScreen)
    // since it's also used to prefill text when editing a past message.
    super.dispose();
  }

  bool get _canSend =>
      (_hasText ||
          _pendingImages.isNotEmpty ||
          _pendingVideos.isNotEmpty ||
          _pendingTextFiles.isNotEmpty) &&
      !widget.isSending;

  void _submit() {
    if (!_canSend) return;
    HapticFeedback.lightImpact();
    final text = _controller.text;
    final images = _pendingImages
        .map((p) => ImageAttachment(base64: base64Encode(p.bytes), mimeType: p.mimeType))
        .toList();
    final videos = _pendingVideos
        .map((v) => VideoAttachment(
              base64: base64Encode(v.bytes),
              mimeType: v.mimeType,
              fileName: v.fileName,
            ))
        .toList();
    final textFiles = _pendingTextFiles
        .map((f) => TextFileAttachment(name: f.name, content: f.content))
        .toList();

    widget.onSend(text, images, videos, textFiles);
    _controller.clear();
    setState(() {
      _pendingImages.clear();
      _pendingVideos.clear();
      _pendingTextFiles.clear();
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    Navigator.of(context).pop(); // close the attach sheet
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1440,
        imageQuality: 70, // keep the base64 payload reasonable over a local link
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final mimeType = _guessImageMimeType(file.path);
      setState(() => _pendingImages.add(_PendingImage(bytes: bytes, mimeType: mimeType)));
    } catch (e) {
      _showError('Could not get that image: $e');
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    Navigator.of(context).pop(); // close the attach sheet
    try {
      final XFile? file = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 30), // only enforced for camera recording
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxVideoBytes) {
        _showError(
          'That video is ${(bytes.length / (1024 * 1024)).toStringAsFixed(1)}MB — '
          'the limit is ${_maxVideoBytes ~/ (1024 * 1024)}MB. Try a shorter clip.',
        );
        return;
      }
      final mimeType = _guessVideoMimeType(file.path);
      final name = file.path.split('/').last;
      setState(() =>
          _pendingVideos.add(_PendingVideo(bytes: bytes, mimeType: mimeType, fileName: name)));
    } catch (e) {
      _showError('Could not get that video: $e');
    }
  }

  Future<void> _pickCodeFile() async {
    Navigator.of(context).pop(); // close the attach sheet
    try {
      final result = await FilePicker.platform.pickFiles(withData: true, type: FileType.any);
      final picked = result?.files.single;
      if (picked == null || picked.bytes == null) return;
      final extracted = FileAttachmentService.extract(picked.name, picked.bytes!);
      setState(() => _pendingTextFiles.addAll(extracted));
    } on FormatException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Could not read that file: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _guessImageMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  String _guessVideoMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    return 'video/mp4';
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose photo'),
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take photo'),
                  onTap: () => _pickImage(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: const Text('Choose video'),
                  subtitle: Text('Max ${_maxVideoBytes ~/ (1024 * 1024)}MB — depends on the model'),
                  onTap: () => _pickVideo(ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.videocam),
                  title: const Text('Record video'),
                  onTap: () => _pickVideo(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: const Text('Add code file or .zip'),
                  subtitle: const Text('Text/code files only — extracted as plain text'),
                  onTap: _pickCodeFile,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.editingBannerText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 8, right: 4),
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined,
                        size: 14,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.editingBannerText!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    InkWell(
                      onTap: widget.onCancelEdit,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
            // Every attachment kind renders as one fixed-height, horizontally
            // scrolling strip — regardless of how many files are attached
            // (even a zip with 50 files), this can never grow to fill the
            // screen or block the send button.
            if (_pendingImages.isNotEmpty)
              _AttachmentStrip(
                itemCount: _pendingImages.length,
                itemBuilder: (context, index) => _ImageThumb(
                  bytes: _pendingImages[index].bytes,
                  onRemove: () => setState(() => _pendingImages.removeAt(index)),
                ),
              ),
            if (_pendingVideos.isNotEmpty)
              _AttachmentStrip(
                itemCount: _pendingVideos.length,
                itemBuilder: (context, index) => _VideoChip(
                  video: _pendingVideos[index],
                  onRemove: () => setState(() => _pendingVideos.removeAt(index)),
                ),
              ),
            if (_pendingTextFiles.isNotEmpty)
              _AttachmentStrip(
                itemCount: _pendingTextFiles.length,
                itemBuilder: (context, index) => _FileChip(
                  file: _pendingTextFiles[index],
                  onRemove: () => setState(() => _pendingTextFiles.removeAt(index)),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Attach',
                    onPressed: _showAttachSheet,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Message Claude…',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _SendButton(
                    enabled: _canSend || widget.isSending,
                    isSending: widget.isSending,
                    onPressed: widget.isSending ? widget.onStop : _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingImage {
  final Uint8List bytes;
  final String mimeType;
  _PendingImage({required this.bytes, required this.mimeType});
}

class _PendingVideo {
  final Uint8List bytes;
  final String mimeType;
  final String fileName;
  _PendingVideo({required this.bytes, required this.mimeType, required this.fileName});
}

/// A fixed-height (56px), horizontally scrolling row — the one shape every
/// attachment kind uses, so no matter how many items are pending (one
/// photo or fifty files from a zip), this strip takes the same small,
/// predictable amount of vertical space instead of growing to fill the
/// screen.
class _AttachmentStrip extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  const _AttachmentStrip({required this.itemCount, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  final Uint8List bytes;
  final VoidCallback onRemove;
  const _ImageThumb({required this.bytes, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          child: Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover),
        ),
        _RemoveBadge(onTap: onRemove),
      ],
    );
  }
}

class _VideoChip extends StatelessWidget {
  final _PendingVideo video;
  final VoidCallback onRemove;
  const _VideoChip({required this.video, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sizeMb = (video.bytes.length / (1024 * 1024)).toStringAsFixed(1);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam, size: 20),
              const SizedBox(height: 2),
              Text('${sizeMb}MB', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        _RemoveBadge(onTap: onRemove),
      ],
    );
  }
}

class _FileChip extends StatelessWidget {
  final ExtractedTextFile file;
  final VoidCallback onRemove;
  const _FileChip({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sizeKb = (file.content.length / 1024).clamp(0, 999).toStringAsFixed(1);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 72,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.description_outlined, size: 18),
              const SizedBox(height: 2),
              Text(
                file.name.split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              Text('${sizeKb}KB', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        _RemoveBadge(onTap: onRemove),
      ],
    );
  }
}

class _RemoveBadge extends StatelessWidget {
  final VoidCallback onTap;
  const _RemoveBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: -6,
      right: -6,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
          child: const Icon(Icons.close, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final bool isSending;
  final VoidCallback onPressed;

  const _SendButton({required this.enabled, required this.isSending, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.accent : AppColors.accent.withOpacity(0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            isSending ? Icons.stop_rounded : Icons.arrow_upward_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

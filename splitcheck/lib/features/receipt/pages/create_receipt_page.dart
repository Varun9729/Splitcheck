import 'dart:io' if (dart.library.js_interop) 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:splitcheck/features/receipt/data/receipt_repository.dart';
import 'package:splitcheck/models/receipt_model.dart';
import 'package:splitcheck/services/receipt_ai_service.dart';
import 'package:splitcheck/services/storage_service.dart';
import 'package:splitcheck/theme.dart';
import 'package:splitcheck/widgets/slug_gen.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

class CreateReceiptPage extends StatefulWidget {
  const CreateReceiptPage({super.key});

  @override
  State<CreateReceiptPage> createState() => _CreateReceiptPageState();
}

class _CreateReceiptPageState extends State<CreateReceiptPage>
    with SingleTickerProviderStateMixin {
  final ReceiptRepository _receiptRepository = ReceiptRepository();
  final StorageService _storageService = StorageService();
  final ReceiptAiService _receiptAiService = ReceiptAiService();
  final TextEditingController _venmoController = TextEditingController();
  final TextEditingController _tipController = TextEditingController();
  final TextEditingController _joinController = TextEditingController();

  File? _selectedImage;
  Uint8List? _imageBytes;
  bool _isLoading = false;
  String? _errorMessage;

  // Processing step tracking
  int _currentStep = 0; // 0=uploading, 1=reading, 2=creating
  List<String> _foundItemNames = [];

  // Parsed receipt state
  String _placeName = '';
  List<ReceiptItem> _receiptItems = [];
  double _subtotal = 0.0;
  double _tax = 0.0;
  double _tip = 0.0;
  double _total = 0.0;
  String? _receiptId;

  // Split mode: 'items' (per-item claiming) or 'equal' (split equally)
  String _splitMode = 'items';
  int _equalSplitCount = 2;

  @override
  void dispose() {
    _venmoController.dispose();
    _tipController.dispose();
    _joinController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source);

      if (pickedFile == null) return;

      final imageBytes = await pickedFile.readAsBytes();
      final file = kIsWeb ? null : File(pickedFile.path);

      setState(() {
        _selectedImage = file;
        _imageBytes = imageBytes;
        _isLoading = true;
        _errorMessage = null;
        _currentStep = 0;
        _foundItemNames = [];
        _receiptItems = [];
        _placeName = '';
      });

      final receiptId = generateSlug(7);

      // Step 1: Upload
      final imageUrl = await _storageService.uploadReceiptImage(
        file: file,
        slug: receiptId,
        bytes: imageBytes,
      );
      debugPrint('Uploaded imageUrl: $imageUrl');

      if (!mounted) return;
      setState(() => _currentStep = 1);

      // Step 2: AI Parse
      final parsed = await _receiptAiService.parseReceipt(imageUrl);
      debugPrint('Parsed response: $parsed');

      final data = Map<String, dynamic>.from(parsed as Map);
      final rawItems = (data['items'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final items = <ReceiptItem>[
        for (int i = 0; i < rawItems.length; i++)
          ReceiptItem(
            id: 'item_$i',
            itemName: rawItems[i]['itemName']?.toString() ?? 'Unknown item',
            itemPrice: (rawItems[i]['itemPrice'] as num?)?.toDouble() ?? 0.0,
            quantity: (rawItems[i]['quantity'] as num?)?.toInt() ?? 1,
            claimedBy: const [],
            position: i,
          ),
      ];

      if (!mounted) return;
      setState(() {
        _currentStep = 2;
        _foundItemNames = items.map((i) => i.itemName).toList();
      });

      // Brief pause to show "creating" step
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;
      setState(() {
        _receiptId = receiptId;
        _placeName = data['placeName']?.toString() ?? 'Unknown place';
        _subtotal = (data['subtotal'] as num?)?.toDouble() ?? 0.0;
        _tax = (data['tax'] as num?)?.toDouble() ?? 0.0;
        _total = (data['total'] as num?)?.toDouble() ?? 0.0;
        final computedBase = _subtotal + _tax;
        _tip = _total > computedBase ? _total - computedBase : 0.0;
        _tipController.text = _tip > 0 ? _tip.toStringAsFixed(2) : '';
        _receiptItems = items;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('Receipt parsing failed: $e');
      debugPrintStack(stackTrace: st);

      if (!mounted) return;
      String friendly = 'Something went wrong. Please try again.';
      final msg = e.toString().toLowerCase();
      if (msg.contains('quota') || msg.contains('resource_exhausted')) {
        friendly = 'AI service is busy. Please try again in a minute.';
      } else if (msg.contains('not-found') || msg.contains('404')) {
        friendly = 'Could not access the image. Please try uploading again.';
      } else if (msg.contains('permission') || msg.contains('403')) {
        friendly = 'Permission denied. Please check your connection.';
      } else if (msg.contains('network') || msg.contains('timeout')) {
        friendly = 'Network error. Check your internet connection.';
      } else if (msg.contains('putfile') || msg.contains('unimplemented')) {
        friendly = 'Upload not supported on this browser. Try a different one.';
      }
      setState(() {
        _errorMessage = friendly;
        _isLoading = false;
      });
    }
  }

  void _joinReceipt() {
    var input = _joinController.text.trim();
    if (input.isEmpty) return;

    final match = RegExp(r'/r/([a-zA-Z0-9]+)').firstMatch(input);
    if (match != null) {
      input = match.group(1)!;
    }

    context.push('/r/$input');
  }

  ImageProvider get _imageProvider {
    if (kIsWeb && _imageBytes != null) {
      return MemoryImage(_imageBytes!);
    }
    return FileImage(_selectedImage!);
  }

  Widget _buildImageWidget({
    BoxFit fit = BoxFit.contain,
    double? height,
    double? width,
  }) {
    if (kIsWeb && _imageBytes != null) {
      return Image.memory(_imageBytes!, fit: fit, height: height, width: width);
    }
    return Image.file(_selectedImage!, fit: fit, height: height, width: width);
  }

  void _showFullImage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.save_alt),
                onPressed: () => _saveImageToDevice(),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: _buildImageWidget(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveImageToDevice() async {
    if (_imageBytes == null) return;
    try {
      if (kIsWeb) {
        // On web, trigger a download
        // ignore: avoid_web_libraries_in_flutter
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Long-press the image to save on web')),
        );
        return;
      }
      await ImageGallerySaverPlus.saveImage(
        _imageBytes!,
        quality: 100,
        name: 'splitcheck_receipt_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt image saved to gallery!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<void> _saveReceipt() async {
    if (_receiptItems.isEmpty || _receiptId == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User not signed in')));
      return;
    }

    final receipt = Receipt(
      id: _receiptId!,
      placeName: _placeName.isNotEmpty ? _placeName : 'Restaurant',
      ownerVenmo: _venmoController.text.trim(),
      ownerUid: user.uid,
      imageUrl: null,
      subtotal: _subtotal,
      tax: _tax,
      tip: _tip,
      splitMode: _splitMode,
      equalSplitCount: _equalSplitCount,
      total: _subtotal + _tax + _tip,
      createdAt: DateTime.now(),
      status: 'ready',
    );

    try {
      await _receiptRepository.saveReceipt(receipt, _receiptItems);
      if (!mounted) return;
      context.push('/r/${receipt.id}');
    } catch (e) {
      if (!mounted) return;
      debugPrint('Failed to save receipt: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show processing screen
    if (_isLoading) return _buildProcessingScreen();

    // Show review screen after parsing
    if (_receiptItems.isNotEmpty) return _buildReviewScreen();

    // Default: home/landing screen
    return _buildHomeScreen();
  }

  // ─── HOME SCREEN ──────────────────────────────────────────────

  Widget _buildHomeScreen() {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 48),

              // Logo
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.receipt_long,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  children: [
                    TextSpan(text: 'Split'),
                    TextSpan(
                      text: 'check',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Tagline
              const Text(
                'Snap the receipt.\nSplit the bill.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Upload your receipt and let me do the math.\nEveryone picks what they ordered,\npays what they owe.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 32),

              // Flow illustration
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildFlowIcon(Icons.receipt_long, AppColors.surfaceVariant),
                  _buildFlowDash(),
                  // _buildFlowAvatars(),
                  // _buildFlowDash(),
                  _buildFlowIcon(Icons.attach_money, AppColors.surfaceVariant),
                ],
              ),

              const SizedBox(height: 32),

              // Error message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Join receipt field
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _joinController,
                      decoration: const InputDecoration(
                        hintText: 'Paste link to join a receipt',
                        isDense: true,
                        prefixIcon: Icon(Icons.link, size: 20),
                      ),
                      onSubmitted: (_) => _joinReceipt(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _joinReceipt,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(56, 48),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('Go'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              const SizedBox(height: 10),

              FilledButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take Photo'),
              ),
              const SizedBox(height: 10),

              // Upload button
              FilledButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Upload Receipt'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlowIcon(IconData icon, Color bg) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppColors.textSecondary, size: 30),
    );
  }

  Widget _buildFlowDash() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        width: 80,
        child: Divider(
          color: AppColors.primary.withValues(alpha: 0.4),
          thickness: 2,
        ),
      ),
    );
  }

  // ─── PROCESSING SCREEN ────────────────────────────────────────

  Widget _buildProcessingScreen() {
    final steps = [
      'Uploading receipt',
      'Reading items',
      'Creating shared bill',
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // Image preview with overlay
              if (_selectedImage != null || _imageBytes != null)
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    image: DecorationImage(
                      image: _imageProvider,
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.3),
                        BlendMode.darken,
                      ),
                    ),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white, size: 32),
                      SizedBox(height: 8),
                      Text(
                        'Analyzing receipt...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 32),

              // Step indicators
              ...List.generate(steps.length, (i) {
                final isDone = _currentStep > i;
                final isCurrent = _currentStep == i;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isDone
                              ? AppColors.primary
                              : isCurrent
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : AppColors.surfaceVariant,
                          shape: BoxShape.circle,
                        ),
                        child: isDone
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 18,
                              )
                            : isCurrent
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: Padding(
                                  padding: EdgeInsets.all(7),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.circle,
                                size: 8,
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        steps[i],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isDone || isCurrent
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }),

              // Found items chips
              if (_foundItemNames.isNotEmpty) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Found items:',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _foundItemNames
                      .map(
                        (name) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── REVIEW SCREEN ────────────────────────────────────────────

  Widget _buildReviewScreen() {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _receiptItems = [];
                        _receiptId = null;
                        _selectedImage = null;
                      });
                    },
                    child: const Icon(Icons.arrow_back_ios, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _placeName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _formatDate(DateTime.now()),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedImage != null || _imageBytes != null)
                    GestureDetector(
                      onTap: () => _showFullImage(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          image: DecorationImage(
                            image: _imageProvider,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            const Divider(),

            // Items list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                children: [
                  ..._receiptItems.asMap().entries.map(
                    (entry) => _buildEditableItem(entry.key, entry.value),
                  ),

                  // Add item button
                  GestureDetector(
                    onTap: _addNewItem,
                    child: Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 16),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: AppColors.primary, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Add Item',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Tip section
                  const Text(
                    'Tip',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ...[15, 18, 20, 22].map(
                        (pct) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _buildTipPill(pct),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _tipController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            prefixText: '\$ ',
                            hintText: '0.00',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _tip = double.tryParse(val) ?? 0.0;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Totals
                  _buildTotalRow('Subtotal', _subtotal),
                  if (_tax > 0) _buildTotalRow('Tax', _tax),
                  if (_tip > 0)
                    _buildTotalRow('Tip (${_getTipPercent()})', _tip),
                  const Divider(height: 24),
                  _buildTotalRow(
                    'Total',
                    _subtotal + _tax + _tip,
                    isTotal: true,
                  ),

                  const SizedBox(height: 24),

                  // How to split
                  const Text(
                    'How to split?',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSplitModeSelector(),

                  const SizedBox(height: 20),

                  // Payment handle (optional)
                  TextField(
                    controller: _venmoController,
                    decoration: const InputDecoration(
                      labelText: 'Payment handle (optional)',
                      prefixText: '@',
                      hintText: 'Venmo, Zelle, etc.',
                      helperText: 'Where friends should send payment',
                    ),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),

            // Bottom button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: FilledButton.icon(
                onPressed: _saveReceipt,
                icon: const Icon(Icons.check, size: 20),
                label: const Text('Looks Good'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableItem(int index, ReceiptItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.quantity > 1
                  ? '${item.quantity}x ${item.itemName}'
                  : item.itemName,
              style: const TextStyle(fontSize: 15),
            ),
          ),
          Text(
            '\$${item.itemPrice.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _editItem(index),
            child: Icon(
              Icons.edit_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _deleteItem(index),
            child: Icon(
              Icons.delete_outline,
              size: 18,
              color: AppColors.error.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode toggle
        Row(
          children: [
            _buildModeChip(
              label: 'By items',
              icon: Icons.checklist,
              isSelected: _splitMode == 'items',
              onTap: () => setState(() => _splitMode = 'items'),
            ),
            const SizedBox(width: 8),
            _buildModeChip(
              label: 'Split equally',
              icon: Icons.people,
              isSelected: _splitMode == 'equal',
              onTap: () => setState(() => _splitMode = 'equal'),
            ),
          ],
        ),

        // Equal split options
        if (_splitMode == 'equal') ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Split between how many people?',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ...[2, 3, 4, 5, 6].map(
                      (n) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setState(() => _equalSplitCount = n),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _equalSplitCount == n
                                  ? AppColors.primary
                                  : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                '$n',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: _equalSplitCount == n
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _showCustomEqualSplit,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _equalSplitCount > 6
                              ? AppColors.primary
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            _equalSplitCount > 6 ? '$_equalSplitCount' : '#',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _equalSplitCount > 6
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Each person pays',
                        style: TextStyle(fontSize: 14),
                      ),
                      Text(
                        '\$${((_subtotal + _tax + _tip) / _equalSplitCount).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        if (_splitMode == 'items') ...[
          const SizedBox(height: 8),
          Text(
            'Friends will pick what they ordered when they open the link.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _buildModeChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.cardBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomEqualSplit() async {
    final controller = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Padding(
          padding: const EdgeInsets.all(15.0),
          child: const Text('Split between how many?'),
        ),
        content: Padding(
          padding: const EdgeInsets.all(15.0),
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'e.g. 8'),
            onSubmitted: (val) {
              final n = int.tryParse(val);
              if (n != null && n > 1) Navigator.of(ctx).pop(n);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n != null && n > 1) Navigator.of(ctx).pop(n);
            },
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => _equalSplitCount = result);
    }
  }

  Widget _buildTipPill(int percent) {
    final tipAmount = _subtotal * percent / 100;
    final isSelected = (_tip - tipAmount).abs() < 0.01 && _tip > 0;

    return GestureDetector(
      onTap: () {
        setState(() {
          _tip = tipAmount;
          _tipController.text = tipAmount.toStringAsFixed(2);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.cardBorder,
          ),
        ),
        child: Text(
          '$percent%',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 17 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 17 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String _getTipPercent() {
    if (_subtotal <= 0) return '';
    final pct = (_tip / _subtotal * 100).round();
    return '$pct%';
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _editItem(int index) async {
    final item = _receiptItems[index];
    final nameCtrl = TextEditingController(text: item.itemName);
    final priceCtrl = TextEditingController(
      text: item.itemPrice.toStringAsFixed(2),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Item name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Price',
                prefixText: '\$ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() {
        _receiptItems[index].itemName = nameCtrl.text.trim();
        _receiptItems[index].itemPrice =
            double.tryParse(priceCtrl.text) ?? item.itemPrice;
        _subtotal = _receiptItems.fold(0, (sum, i) => sum + i.itemPrice);
      });
    }
  }

  void _deleteItem(int index) {
    setState(() {
      _receiptItems.removeAt(index);
      _subtotal = _receiptItems.fold(0, (sum, i) => sum + i.itemPrice);
    });
  }

  void _addNewItem() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Item name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Price',
                prefixText: '\$ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true && nameCtrl.text.trim().isNotEmpty) {
      setState(() {
        _receiptItems.add(
          ReceiptItem(
            id: 'item_${_receiptItems.length}',
            itemName: nameCtrl.text.trim(),
            itemPrice: double.tryParse(priceCtrl.text) ?? 0.0,
            position: _receiptItems.length,
          ),
        );
        _subtotal = _receiptItems.fold(0, (sum, i) => sum + i.itemPrice);
      });
    }
  }
}

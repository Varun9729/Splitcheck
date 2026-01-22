import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:splitcheck/features/receipt/data/receipt_repository.dart';
import 'package:splitcheck/features/utils/receipt_parser.dart';
import 'package:splitcheck/models/receipt_model.dart';
import 'package:splitcheck/widgets/slug_gen.dart';
import 'package:splitcheck/services/vision_service.dart';

class CreateReceiptPage extends StatefulWidget {
  const CreateReceiptPage({super.key});

  @override
  State<CreateReceiptPage> createState() => _CreateReceiptPageState();
}

class _CreateReceiptPageState extends State<CreateReceiptPage> {
  final repository = ReceiptRepository();
  final ImagePicker _picker = ImagePicker();
  final visionService = VisionService(
    'AIzaSyAL5K46AZT_FvXa6sZTqXTk5bBF887e8v4',
  );

  // Controller for editable field
  final _venmoController = TextEditingController(text: "@varun");

  File? _pickedImage;
  String rawText = '';
  String placeName = '';
  List<ReceiptItem> receiptItems = [];
  double tip = 0.0;
  double subtotal = 0.0;
  double tax = 0.0;
  double total = 0.0;

  bool isLoading = false;
  bool showRawText = false;

  @override
  void dispose() {
    _venmoController.dispose();
    super.dispose();
  }

  // Pick image from camera or gallery
  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile == null) return;

    setState(() {
      isLoading = true;
      _pickedImage = File(pickedFile.path);
      // Clear previous data
      receiptItems.clear();
      rawText = '';
      subtotal = 0.0;
      tax = 0.0;
      tip = 0.0;
      total = 0.0;
    });

    try {
      final extractedText = await visionService.extractTextFromImage(
        File(pickedFile.path),
      );

      final parsed = parseReceiptText(extractedText);

      setState(() {
        rawText = extractedText;
        receiptItems = parsed.items;

        // Extract place name (first meaningful line)
        final lines = extractedText.split('\n');
        placeName = _extractPlaceName(lines);

        subtotal = parsed.subtotal;
        tax = parsed.tax;
        tip = parsed.tip;
        total = parsed.total;

        // Debug logging
        print("=== PARSING DEBUG ===");
        print("Raw text length: ${rawText.length}");
        print("Items found: ${receiptItems.length}");
        print("Subtotal: $subtotal");
        print("Tax: $tax");
        print("Tip: $tip");
        print("Total: $total");
        print("Place name: $placeName");
        for (int i = 0; i < receiptItems.length; i++) {
          print(
            "Item $i: ${receiptItems[i].itemName} - \$${receiptItems[i].itemPrice.toStringAsFixed(2)}",
          );
        }
        print("===================");

        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      print("OCR failed: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('OCR failed: $e')));
    }
  }

  String _extractPlaceName(List<String> lines) {
    for (final line in lines) {
      final cleaned = line.trim();
      if (cleaned.isNotEmpty &&
          !cleaned.toLowerCase().contains('street') &&
          !cleaned.toLowerCase().contains('server') &&
          !cleaned.toLowerCase().contains('check') &&
          cleaned.length > 3) {
        return cleaned;
      }
    }
    return 'Restaurant';
  }

  // Save receipt to Firestore
  Future<void> _saveReceipt() async {
    if (receiptItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items detected from receipt')),
      );
      return;
    }

    if (_venmoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your Venmo handle')),
      );
      return;
    }

    final slug = generateSlug(8);
    final receipt = Receipt(
      id: slug,
      placeName: placeName,
      ownerVenmo: _venmoController.text.trim(),
      items: receiptItems,
      tip: tip,
      createdAt: DateTime.now(),
    );

    try {
      await repository.saveReceipt(receipt);
      print("Receipt saved successfully: $slug");
      context.go('/r/$slug');
    } catch (e) {
      print("Error saving receipt: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Receipt'),
        actions: [
          IconButton(
            icon: Icon(showRawText ? Icons.visibility_off : Icons.visibility),
            onPressed: () {
              setState(() {
                showRawText = !showRawText;
              });
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Pick Image Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text("Camera"),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo),
                        label: const Text("Gallery"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Show selected image and parsed data
                  if (_pickedImage != null) ...[
                    GestureDetector(
                      onTap: () {
                        if (_pickedImage != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => Scaffold(
                                backgroundColor: Colors.black,
                                body: GestureDetector(
                                  onTap: () => Navigator.of(context).pop(),
                                  child: Center(
                                    child: Hero(
                                      tag: 'pickedImage',
                                      child: InteractiveViewer(
                                        minScale: 0.5,
                                        maxScale: 5.0,
                                        child: Image.file(_pickedImage!),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                      },
                      child: Hero(
                        tag: 'pickedImage',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _pickedImage!,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ADD THE DEBUG BUTTON HERE
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              showRawText = !showRawText;
                            });
                          },
                          icon: Icon(
                            showRawText
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          label: Text(
                            showRawText ? "Hide Raw Text" : "Show Raw Text",
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Show raw OCR text (for debugging)
                  if (showRawText && rawText.isNotEmpty) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Raw OCR Text:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              rawText,
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Parsed Receipt Data or Debug Info
                  if (receiptItems.isNotEmpty) ...[
                    _buildReceiptSummary(),
                    const SizedBox(height: 24),
                  ] else if (rawText.isNotEmpty) ...[
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.warning, color: Colors.red.shade600),
                                const SizedBox(width: 8),
                                Text(
                                  'Parsing Issues Detected',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text('Subtotal: \$${subtotal.toStringAsFixed(2)}'),
                            Text('Tax: \$${tax.toStringAsFixed(2)}'),
                            Text('Tip: \$${tip.toStringAsFixed(2)}'),
                            Text('Total: \$${total.toStringAsFixed(2)}'),
                            const SizedBox(height: 8),
                            const Text(
                              'Toggle the eye icon above to see the raw OCR text and help debug the parsing.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Venmo handle input
                  if (receiptItems.isNotEmpty) ...[
                    TextField(
                      controller: _venmoController,
                      decoration: const InputDecoration(
                        labelText: "Your Venmo Handle",
                        border: OutlineInputBorder(),
                        prefixText: "@",
                        helperText: "Where friends should send payment",
                      ),
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: _saveReceipt,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text(
                        "Create & Share Receipt",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildReceiptSummary() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Restaurant name header
            Row(
              children: [
                const Icon(Icons.restaurant, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    placeName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Items list
            Text(
              'Items Ordered:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),

            ...receiptItems.asMap().entries.map((entry) {
              int index = entry.key;
              ReceiptItem item = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.itemName,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    Text(
                      '${item.itemPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            // Totals section
            _buildSummaryRow("Subtotal", subtotal),
            const SizedBox(height: 8),
            if (tax > 0) ...[
              _buildSummaryRow("Tax", tax),
              const SizedBox(height: 8),
            ],
            // if (tip > 0) ...[
            _buildSummaryRow("Tip", tip),
            const SizedBox(height: 8),
            // ],
            const Divider(),
            const SizedBox(height: 8),
            _buildSummaryRow("Total", total, isTotal: true),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Share the link with friends so they can select their items and pay you back!',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: isTotal ? 16 : 14,
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: isTotal ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

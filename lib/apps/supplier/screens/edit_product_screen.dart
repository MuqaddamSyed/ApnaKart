import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/product.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';

/// Add/Edit product: photo upload, fields, auto discount %.
class EditProductScreen extends ConsumerStatefulWidget {
  final String? productId;
  const EditProductScreen({super.key, this.productId});
  @override
  ConsumerState<EditProductScreen> createState() => _State();
}

class _State extends ConsumerState<EditProductScreen> {
  final _name = TextEditingController();
  final _mrp = TextEditingController();
  final _sale = TextEditingController();
  final _stock = TextEditingController();
  String _unit = 'piece';
  String _category = AppConstants.productCategories.first;
  bool _available = true;
  File? _image;
  String? _imageUrl;
  bool _saving = false;
  bool _adminManaged = false;

  @override
  void initState() { super.initState(); if (widget.productId != null) _loadExisting(); }

  Future<void> _loadExisting() async {
    final row = await supabase.from('products').select().eq('id', widget.productId!).single();
    final p = Product.fromMap(row);
    _name.text = p.name;
    _mrp.text = p.mrp.toString();
    _sale.text = p.salePrice.toString();
    _stock.text = p.stockQty.toString();
    _unit = p.unit ?? 'piece';
    _category = AppConstants.productCategories.contains(p.category)
        ? p.category!
        : AppConstants.productCategories.first;
    _available = p.isAvailable;
    _imageUrl = p.imageUrl;
    _adminManaged = p.adminManaged;
    setState(() {});
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (x != null) setState(() => _image = File(x.path));
  }

  int get _discount {
    final m = double.tryParse(_mrp.text) ?? 0;
    final s = double.tryParse(_sale.text) ?? 0;
    return discountPercent(m, s);
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : null,
    ));
  }

  Future<void> _save() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      _snack('You are signed out. Please log in again.', error: true);
      return;
    }
    final mrp = double.tryParse(_mrp.text);
    final sale = double.tryParse(_sale.text);
    if (_name.text.trim().isEmpty) {
      return _snack('Product name is required', error: true);
    }
    if (mrp == null || mrp <= 0 || sale == null || sale <= 0) {
      return _snack('Enter a valid MRP and sale price', error: true);
    }
    if (sale > mrp) {
      return _snack('Sale price cannot be higher than MRP', error: true);
    }
    setState(() => _saving = true);
    try {
      String? imageUrl = _imageUrl;
      if (_image != null) {
        imageUrl = await ref.read(productServiceProvider)
            .uploadProductImage(_image!, '${DateTime.now().millisecondsSinceEpoch}.jpg');
      }
      final data = {
        if (!_adminManaged) 'supplier_id': uid,
        if (!_adminManaged) 'name': _name.text.trim(),
        if (!_adminManaged) 'category': _category,
        if (!_adminManaged) 'unit': _unit,
        if (!_adminManaged) 'mrp': mrp,
        'sale_price': sale,
        if (!_adminManaged) 'stock_qty': int.tryParse(_stock.text) ?? 0,
        'is_available': _available,
        if (!_adminManaged && imageUrl != null) 'image_url': imageUrl,
      };
      if (widget.productId == null) {
        await supabase.from('products').insert(data);
      } else {
        await supabase.from('products').update(data).eq('id', widget.productId!);
      }
      if (mounted) context.pop();
    } catch (e) {
      _snack('Could not save product: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.productId == null ? 'Add Product' : 'Edit Product')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Image: locked for admin-managed products.
          if (_adminManaged)
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                image: _imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(_imageUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: _imageUrl == null
                  ? const Center(
                      child: Text('Image managed by admin',
                          style: TextStyle(color: AppColors.textMuted)))
                  : null,
            )
          else
            GestureDetector(
              onTap: _pick,
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  image: _image != null
                      ? DecorationImage(
                          image: FileImage(_image!), fit: BoxFit.cover)
                      : (_imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(_imageUrl!),
                              fit: BoxFit.cover)
                          : null),
                ),
                child: (_image == null && _imageUrl == null)
                    ? const Center(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Icon(Icons.add_a_photo, color: AppColors.textMuted),
                          Text('Add photo',
                              style: TextStyle(color: AppColors.textMuted)),
                        ]))
                    : null,
              ),
            ),
          const SizedBox(height: 16),
          // Name: locked for admin-managed products.
          if (_adminManaged)
            InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Product name', filled: true),
              child: Text(_name.text,
                  style: const TextStyle(color: AppColors.textMuted)),
            )
          else
            TextField(
                controller: _name,
                decoration:
                    const InputDecoration(labelText: 'Product name')),
          const SizedBox(height: 12),
          DropdownButtonFormField(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: AppConstants.productCategories
                .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _category = v ?? AppConstants.productCategories.first),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField(
            value: _unit,
            decoration: const InputDecoration(labelText: 'Unit'),
            items: const ['500g','1kg','5kg','500ml','1L','piece','dozen']
                .map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
            onChanged: (v) => setState(() => _unit = v ?? 'piece'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _mrp, keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'MRP (Rs.)'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _sale, keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Sale price (Rs.)'))),
          ]),
          const SizedBox(height: 8),
          Text('Discount: $_discount%', style: const TextStyle(color: AppColors.secondary)),
          const SizedBox(height: 12),
          TextField(controller: _stock, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stock quantity')),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _available,
            activeColor: AppColors.secondary,
            title: const Text('Available'),
            onChanged: (v) => setState(() => _available = v),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}

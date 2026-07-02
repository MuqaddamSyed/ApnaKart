import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/supplier.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import 'admin_ui.dart';

/// Admin product catalog: add/edit admin-managed products.
/// Suppliers only set sale_price on these; name/image/MRP are locked.
class AdminCatalogScreen extends StatefulWidget {
  const AdminCatalogScreen({super.key});
  @override
  State<AdminCatalogScreen> createState() => _State();
}

class _State extends State<AdminCatalogScreen> {
  List<Product> _products = [];
  List<Supplier> _suppliers = [];
  String _filterCategory = 'All';
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final products = await supabase
        .from('products')
        .select()
        .order('name', ascending: true);
    final suppliers = await supabase.from('suppliers').select();
    if (mounted) {
      setState(() {
        _products = (products as List).map((e) => Product.fromMap(e)).toList();
        _suppliers =
            (suppliers as List).map((e) => Supplier.fromMap(e)).toList();
        _loading = false;
      });
    }
  }

  List<Product> get _filtered {
    return _products.where((p) {
      final matchCat =
          _filterCategory == 'All' || p.category == _filterCategory;
      final matchSearch = _search.isEmpty ||
          p.name.toLowerCase().contains(_search.toLowerCase());
      return matchCat && matchSearch;
    }).toList();
  }

  void _openEditor({Product? product}) {
    showDialog(
      context: context,
      builder: (_) => _ProductDialog(
        product: product,
        suppliers: _suppliers,
        onSaved: _load,
      ),
    );
  }

  Future<void> _toggleAdminManaged(Product p, bool v) async {
    await supabase
        .from('products')
        .update({'admin_managed': v})
        .eq('id', p.id);
    _load();
  }

  Future<void> _toggleAvailable(Product p, bool v) async {
    await supabase
        .from('products')
        .update({'is_available': v})
        .eq('id', p.id);
    _load();
  }

  Future<void> _delete(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove "${p.name}" from the catalog?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await supabase.from('products').delete().eq('id', p.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ['All', ...AppConstants.productCategories];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminPageTitle(
            'Product Catalog',
            trailing: ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Product'),
              onPressed: () => _openEditor(),
            ),
          ),
          // Filters row.
          Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search products...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _filterCategory,
              items: categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _filterCategory = v ?? 'All'),
            ),
          ]),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('No products found'))
                    : AdminCard(
                        padding: EdgeInsets.zero,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              columnSpacing: 20,
                              columns: const [
                                DataColumn(label: Text('Image')),
                                DataColumn(label: Text('Name')),
                                DataColumn(label: Text('Category')),
                                DataColumn(label: Text('MRP')),
                                DataColumn(label: Text('Supplier')),
                                DataColumn(label: Text('Admin Lock')),
                                DataColumn(label: Text('Available')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: _filtered.map((p) {
                                final supplier = _suppliers
                                    .where((s) => s.id == p.supplierId)
                                    .firstOrNull;
                                return DataRow(cells: [
                                  DataCell(p.imageUrl != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image.network(p.imageUrl!,
                                              width: 40,
                                              height: 40,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(Icons.image_not_supported,
                                                      size: 32, color: AppColors.textMuted)),
                                        )
                                      : const Icon(Icons.inventory_2,
                                          color: AppColors.textMuted, size: 32)),
                                  DataCell(Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(p.name,
                                          style: const TextStyle(fontWeight: FontWeight.w600)),
                                      Text(p.unit ?? '',
                                          style: const TextStyle(
                                              fontSize: 11, color: AppColors.textMuted)),
                                    ],
                                  )),
                                  DataCell(Text(p.category ?? '-')),
                                  DataCell(Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(formatRupees(p.mrp)),
                                      if (p.salePrice < p.mrp)
                                        Text(
                                          '${p.discountPercent}% off',
                                          style: const TextStyle(
                                              fontSize: 11, color: AppColors.secondary),
                                        ),
                                    ],
                                  )),
                                  DataCell(Text(
                                      supplier?.shopName ?? p.supplierId.substring(0, 8),
                                      style: const TextStyle(fontSize: 13))),
                                  DataCell(Switch(
                                    value: p.adminManaged,
                                    activeColor: AppColors.primary,
                                    onChanged: (v) => _toggleAdminManaged(p, v),
                                  )),
                                  DataCell(Switch(
                                    value: p.isAvailable,
                                    activeColor: AppColors.secondary,
                                    onChanged: (v) => _toggleAvailable(p, v),
                                  )),
                                  DataCell(Row(children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 18, color: AppColors.primary),
                                      tooltip: 'Edit',
                                      onPressed: () => _openEditor(product: p),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18, color: AppColors.danger),
                                      tooltip: 'Delete',
                                      onPressed: () => _delete(p),
                                    ),
                                  ])),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// Add / Edit product dialog.
class _ProductDialog extends StatefulWidget {
  final Product? product;
  final List<Supplier> suppliers;
  final VoidCallback onSaved;
  const _ProductDialog(
      {this.product, required this.suppliers, required this.onSaved});

  @override
  State<_ProductDialog> createState() => _DialogState();
}

class _DialogState extends State<_ProductDialog> {
  final _name = TextEditingController();
  final _imageUrl = TextEditingController();
  final _mrp = TextEditingController();
  final _description = TextEditingController();
  String _category = AppConstants.productCategories.first;
  String _unit = 'piece';
  String? _supplierId;
  bool _adminManaged = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _name.text = p.name;
      _imageUrl.text = p.imageUrl ?? '';
      _mrp.text = p.mrp.toString();
      _description.text = p.description ?? '';
      _category = AppConstants.productCategories.contains(p.category)
          ? p.category!
          : AppConstants.productCategories.first;
      _unit = p.unit ?? 'piece';
      _supplierId = p.supplierId;
      _adminManaged = p.adminManaged;
    } else if (widget.suppliers.isNotEmpty) {
      _supplierId = widget.suppliers.first.id;
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    if (_supplierId == null) return;
    final mrp = double.tryParse(_mrp.text);
    if (mrp == null || mrp <= 0) return;

    setState(() => _saving = true);
    try {
      final data = {
        'supplier_id': _supplierId,
        'name': _name.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'image_url':
            _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
        'category': _category,
        'unit': _unit,
        'mrp': mrp,
        'sale_price': mrp, // default sale = MRP; supplier can edit
        'is_available': true,
        'admin_managed': _adminManaged,
      };
      if (widget.product == null) {
        await supabase.from('products').insert(data);
      } else {
        await supabase
            .from('products')
            .update(data)
            .eq('id', widget.product!.id);
      }
      if (mounted) Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.product == null ? 'Add Product' : 'Edit Product',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _name,
                  decoration:
                      const InputDecoration(labelText: 'Product name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _imageUrl,
                  decoration: const InputDecoration(
                    labelText: 'Image URL',
                    hintText: 'https://...',
                  ),
                ),
                const SizedBox(height: 12),
                // Live image preview.
                if (_imageUrl.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _imageUrl.text,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 60,
                          color: Colors.grey[100],
                          child: const Center(
                              child: Text('Invalid image URL',
                                  style:
                                      TextStyle(color: AppColors.textMuted))),
                        ),
                      ),
                    ),
                  ),
                TextField(
                  controller: _description,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Description (optional)'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: AppConstants.productCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(
                          () => _category = v ?? AppConstants.productCategories.first),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: const [
                        '500g', '1kg', '5kg', '500ml', '1L', 'piece', 'dozen'
                      ]
                          .map((u) =>
                              DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _unit = v ?? 'piece'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _mrp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'MRP (₹) *',
                      helperText: 'Supplier sets their own sale price'),
                ),
                const SizedBox(height: 12),
                if (widget.suppliers.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _supplierId,
                    decoration: const InputDecoration(labelText: 'Assign to supplier'),
                    items: widget.suppliers
                        .map((s) => DropdownMenuItem(
                            value: s.id, child: Text(s.shopName)))
                        .toList(),
                    onChanged: (v) => setState(() => _supplierId = v),
                  ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _adminManaged,
                  activeColor: AppColors.primary,
                  title: const Text('Admin managed',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'When on, supplier can only edit sale price — not name or image'),
                  onChanged: (v) => setState(() => _adminManaged = v),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(widget.product == null ? 'Add' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

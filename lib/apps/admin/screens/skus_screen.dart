import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/utils/formatters.dart';
import 'admin_ui.dart';

/// Master SKU catalog — a library of common products (name, image, category,
/// optional price) the admin builds up. Every field is optional.
class AdminSkusScreen extends StatefulWidget {
  const AdminSkusScreen({super.key});
  @override
  State<AdminSkusScreen> createState() => _State();
}

class _State extends State<AdminSkusScreen> {
  List<Map<String, dynamic>> _skus = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await supabase
        .from('skus')
        .select()
        .order('created_at', ascending: false);
    _skus = (rows as List).cast<Map<String, dynamic>>();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _delete(String id) async {
    await supabase.from('skus').delete().eq('id', id);
    _load();
  }

  Future<void> _openForm() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _SkuDialog(),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminPageTitle(
            'Product Catalog (SKUs)',
            trailing: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add SKU'),
              onPressed: _openForm,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'A library of common products. Add name, image and category now — '
            'price is optional and can be filled later.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _skus.isEmpty
                    ? const Center(child: Text('No SKUs yet — add your first one'))
                    : AdminCard(
                        padding: EdgeInsets.zero,
                        child: ListView.separated(
                          itemCount: _skus.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final s = _skus[i];
                            final img = s['image_url'] as String?;
                            final mrp = (s['mrp'] as num?)?.toDouble();
                            final sp = (s['sale_price'] as num?)?.toDouble();
                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: img == null || img.isEmpty
                                      ? Container(
                                          color: AppColors.background,
                                          child: const Icon(Icons.inventory_2,
                                              color: AppColors.textMuted))
                                      : Image.network(img,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                                  Icons.image_not_supported,
                                                  color: AppColors.textMuted)),
                                ),
                              ),
                              title: Text((s['name'] as String?)?.isNotEmpty == true
                                  ? s['name'] as String
                                  : 'Unnamed'),
                              subtitle: Text([
                                if ((s['category'] as String?)?.isNotEmpty == true)
                                  s['category'],
                                if ((s['unit'] as String?)?.isNotEmpty == true)
                                  s['unit'],
                                if (mrp != null) 'MRP ${formatRupees(mrp)}',
                                if (sp != null) 'SP ${formatRupees(sp)}',
                              ].join('  ·  ')),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: AppColors.danger),
                                onPressed: () => _delete(s['id'] as String),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// Add-SKU dialog. Only the name is encouraged; everything else is optional.
class _SkuDialog extends StatefulWidget {
  const _SkuDialog();
  @override
  State<_SkuDialog> createState() => _DialogState();
}

class _DialogState extends State<_SkuDialog> {
  final _name = TextEditingController();
  final _imageUrl = TextEditingController();
  final _mrp = TextEditingController();
  final _sale = TextEditingController();
  final _unit = TextEditingController();
  final _description = TextEditingController();
  String? _category;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _imageUrl, _mrp, _sale, _unit, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Only send non-empty fields, so blank optional values stay null.
      final data = <String, dynamic>{};
      void put(String k, String v) {
        if (v.trim().isNotEmpty) data[k] = v.trim();
      }
      void putNum(String k, String v) {
        final n = double.tryParse(v.trim());
        if (n != null) data[k] = n;
      }
      put('name', _name.text);
      put('image_url', _imageUrl.text);
      if (_category != null) data['category'] = _category;
      put('description', _description.text);
      put('unit', _unit.text);
      putNum('mrp', _mrp.text);
      putNum('sale_price', _sale.text);

      await supabase.from('skus').insert(data.isEmpty ? {'name': null} : data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add SKU'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _category,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Category (optional)'),
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('— none —')),
                  ...AppConstants.productCategories.map(
                      (c) => DropdownMenuItem(value: c, child: Text(c))),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _imageUrl,
                decoration: const InputDecoration(
                    labelText: 'Image URL (optional)',
                    hintText: 'https://…'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _unit,
                decoration: const InputDecoration(
                    labelText: 'Unit (optional)', hintText: '1kg, 500ml, piece'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _mrp,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'MRP (optional)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _sale,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Selling price (optional)'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Description (optional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

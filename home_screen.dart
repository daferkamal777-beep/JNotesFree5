import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/stroke.dart';
import '../services/notes_store.dart';
import '../widgets/dialogs.dart';
import '../widgets/page_painter.dart';
import 'editor_screen.dart';

const String _allFolders = 'كل الملاحظات';
const List<String> _folderNames = ['الدراسة', 'العمل', 'شخصي'];

class HomeScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;

  const HomeScreen({super.key, required this.onToggleTheme});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<NoteMeta> _notes = [];
  bool _loading = true;
  int _section = 0; // 0 الملاحظات، 1 المفضلة، 2 المحذوفة
  String _folder = _allFolders;
  bool _searching = false;
  final TextEditingController _searchCtl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await NotesStore.loadIndex();
    if (!mounted) return;
    setState(() {
      _notes = list;
      _loading = false;
    });
  }

  List<NoteMeta> get _visible {
    final q = _query.trim().toLowerCase();
    return _notes.where((n) {
      if (_section == 2) {
        if (!n.trashed) return false;
      } else {
        if (n.trashed) return false;
        if (_section == 1 && !n.favorite) return false;
        if (_folder != _allFolders && n.folder != _folder) return false;
      }
      if (q.isNotEmpty && !n.title.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  // ---------- العمليات ----------

  Future<void> _newNote() async {
    final id = NotesStore.newId();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          noteId: id,
          folder: _folder == _allFolders ? '' : _folder,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _openNote(NoteMeta n) async {
    if (n.trashed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('استعد الملاحظة من القائمة أولًا لتعديلها')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(noteId: n.id, initialTitle: n.title),
      ),
    );
    await _reload();
  }

  Future<void> _toggleFavorite(NoteMeta n) async {
    await NotesStore.updateFlags(n.id, favorite: !n.favorite);
    await _reload();
  }

  Future<void> _rename(NoteMeta n) async {
    final controller = TextEditingController(text: n.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل العنوان'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'عنوان الملاحظة'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await NotesStore.rename(n.id, result);
    await _reload();
  }

  Future<void> _moveToFolder(NoteMeta n) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('نقل إلى مجلد'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('بدون مجلد'),
          ),
          ..._folderNames.map((f) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, f),
                child: Text(f),
              )),
        ],
      ),
    );
    if (result == null) return;
    await NotesStore.updateFlags(n.id, folder: result);
    await _reload();
  }

  Future<void> _moveToTrash(NoteMeta n) async {
    await NotesStore.updateFlags(n.id, trashed: true);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('نُقلت الملاحظة إلى المحذوفة'),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () async {
            await NotesStore.updateFlags(n.id, trashed: false);
            await _reload();
          },
        ),
      ),
    );
  }

  Future<void> _restore(NoteMeta n) async {
    await NotesStore.updateFlags(n.id, trashed: false);
    await _reload();
  }

  Future<void> _deleteForever(NoteMeta n) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف نهائي',
      message: 'سيتم حذف «${n.title}» ومحتواها نهائيًا ولا يمكن استرجاعها. هل تريد المتابعة؟',
      okLabel: 'حذف نهائيًا',
    );
    if (!ok) return;
    await NotesStore.deleteForever(n.id);
    await _reload();
  }

  Future<void> _emptyTrash() async {
    final trashed = _notes.where((n) => n.trashed).toList();
    if (trashed.isEmpty) return;
    final ok = await confirmDialog(
      context,
      title: 'تفريغ المحذوفة',
      message: 'سيتم حذف ${trashed.length} ملاحظة نهائيًا ولا يمكن استرجاعها. هل تريد المتابعة؟',
      okLabel: 'تفريغ',
    );
    if (!ok) return;
    for (final n in trashed) {
      await NotesStore.deleteForever(n.id);
    }
    await _reload();
  }

  // ---------- مساعدات العرض ----------

  String _fmt(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }

  List<String> _emptyText() {
    if (_query.trim().isNotEmpty) {
      return ['لا توجد نتائج', 'جرّب كلمة أخرى في البحث'];
    }
    if (_section == 1) {
      return ['لا توجد ملاحظات مفضلة', 'اختر «إضافة إلى المفضلة» من قائمة الملاحظة'];
    }
    if (_section == 2) {
      return ['المحذوفة فارغة', 'الملاحظات المحذوفة تظهر هنا قبل الحذف النهائي'];
    }
    if (_folder != _allFolders) {
      return ['لا توجد ملاحظات في هذا المجلد', 'اضغط «ملاحظة جديدة» لإضافة ملاحظة إليه'];
    }
    return ['لا توجد ملاحظات بعد', 'اضغط «ملاحظة جديدة» للبدء'];
  }

  PopupMenuButton<String> _menu(NoteMeta n) {
    return PopupMenuButton<String>(
      onSelected: (v) {
        switch (v) {
          case 'rename':
            _rename(n);
            break;
          case 'favorite':
            _toggleFavorite(n);
            break;
          case 'folder':
            _moveToFolder(n);
            break;
          case 'trash':
            _moveToTrash(n);
            break;
          case 'restore':
            _restore(n);
            break;
          case 'delete':
            _deleteForever(n);
            break;
        }
      },
      itemBuilder: (_) => n.trashed
          ? const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'restore', child: Text('استعادة')),
              PopupMenuItem(value: 'delete', child: Text('حذف نهائي')),
            ]
          : <PopupMenuEntry<String>>[
              const PopupMenuItem(value: 'rename', child: Text('تعديل العنوان')),
              PopupMenuItem(
                value: 'favorite',
                child: Text(n.favorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة'),
              ),
              const PopupMenuItem(value: 'folder', child: Text('نقل إلى مجلد')),
              const PopupMenuItem(value: 'trash', child: Text('حذف')),
            ],
    );
  }

  Widget _card(NoteMeta n) {
    final info = StringBuffer(_fmt(n.updatedAt))
      ..write('  •  ${n.pageCount} صفحة');
    if (n.folder.isNotEmpty) info.write('  •  ${n.folder}');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openNote(n),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: NotePreview(
                key: ValueKey('${n.id}_${n.updatedAt.millisecondsSinceEpoch}'),
                noteId: n.id,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          info.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (n.favorite)
                    const Icon(Icons.star, size: 18, color: Colors.amber),
                  _menu(n),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final visible = _visible;
    final empty = _emptyText();

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchCtl,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'ابحث في عناوين الملاحظات',
                  border: InputBorder.none,
                ),
              )
            : const Text(
                'JNotes Free',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
        actions: [
          if (_searching)
            IconButton(
              tooltip: 'إغلاق البحث',
              onPressed: () => setState(() {
                _searching = false;
                _query = '';
                _searchCtl.clear();
              }),
              icon: const Icon(Icons.close),
            )
          else ...[
            IconButton(
              tooltip: 'بحث',
              onPressed: () => setState(() => _searching = true),
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: 'الوضع الليلي',
              onPressed: widget.onToggleTheme,
              icon: const Icon(Icons.dark_mode_outlined),
            ),
            if (_section == 2)
              IconButton(
                tooltip: 'تفريغ المحذوفة',
                onPressed: _emptyTrash,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
          ],
        ],
      ),
      floatingActionButton: _section == 2
          ? null
          : FloatingActionButton.extended(
              onPressed: _newNote,
              icon: const Icon(Icons.add),
              label: const Text('ملاحظة جديدة'),
            ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _section,
              onDestinationSelected: (i) => setState(() => _section = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.notes_outlined),
                  selectedIcon: Icon(Icons.notes),
                  label: 'الملاحظات',
                ),
                NavigationDestination(
                  icon: Icon(Icons.star_border),
                  selectedIcon: Icon(Icons.star),
                  label: 'المفضلة',
                ),
                NavigationDestination(
                  icon: Icon(Icons.delete_outline),
                  selectedIcon: Icon(Icons.delete),
                  label: 'المحذوفة',
                ),
              ],
            ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _section,
              onDestinationSelected: (i) => setState(() => _section = i),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.notes_outlined),
                  selectedIcon: Icon(Icons.notes),
                  label: Text('الملاحظات'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.star_border),
                  selectedIcon: Icon(Icons.star),
                  label: Text('المفضلة'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.delete_outline),
                  selectedIcon: Icon(Icons.delete),
                  label: Text('المحذوفة'),
                ),
              ],
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : CustomScrollView(
                    slivers: [
                      if (_section != 2)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [_allFolders, ..._folderNames]
                                  .map((f) => FilterChip(
                                        label: Text(f),
                                        selected: f == _folder,
                                        onSelected: (_) =>
                                            setState(() => _folder = f),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ),
                      if (visible.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.note_alt_outlined, size: 72),
                                const SizedBox(height: 12),
                                Text(
                                  empty[0],
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(empty[1], textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            _section == 2 ? 16 : 0,
                            16,
                            100,
                          ),
                          sliver: SliverGrid(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _card(visible[index]),
                              childCount: visible.length,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: wide ? 280 : 200,
                              mainAxisExtent: 230,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// معاينة مصغّرة للصفحة الأولى من الملاحظة.
class NotePreview extends StatefulWidget {
  final String noteId;

  const NotePreview({super.key, required this.noteId});

  @override
  State<NotePreview> createState() => _NotePreviewState();
}

class _NotePreviewState extends State<NotePreview> {
  List<InkStroke>? _strokes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final content = await NotesStore.loadContent(widget.noteId);
    if (!mounted) return;
    setState(() {
      _strokes = (content == null || content.pages.isEmpty)
          ? <InkStroke>[]
          : content.pages.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strokes = _strokes;
    if (strokes == null) {
      return const ColoredBox(color: Colors.white, child: SizedBox.expand());
    }
    return CustomPaint(
      painter: _PreviewPainter(strokes),
      child: const SizedBox.expand(),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final List<InkStroke> strokes;

  _PreviewPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    if (strokes.isEmpty) return;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final s in strokes) {
      for (final p in s.points) {
        minX = math.min(minX, p.x);
        minY = math.min(minY, p.y);
        maxX = math.max(maxX, p.x);
        maxY = math.max(maxY, p.y);
      }
    }
    final w = math.max(maxX - minX, 1.0);
    final h = math.max(maxY - minY, 1.0);
    final scale = math.min(
      1.0,
      math.min((size.width - 16) / w, (size.height - 16) / h),
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-(minX + maxX) / 2, -(minY + maxY) / 2);
    paintStrokes(canvas, strokes);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}

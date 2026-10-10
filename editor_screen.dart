import 'dart:async';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/stroke.dart';
import '../services/notes_store.dart';
import '../widgets/dialogs.dart';
import '../widgets/drawing_canvas.dart';

/// بيانات صفحة واحدة مع سجل التراجع/الإعادة الخاص بها.
class _PageData {
  List<InkStroke> strokes;
  PageBackground background;
  final List<List<InkStroke>> undo = [];
  final List<List<InkStroke>> redo = [];

  _PageData({List<InkStroke>? strokes, this.background = PageBackground.blank})
      : strokes = strokes ?? <InkStroke>[];
}

class EditorScreen extends StatefulWidget {
  final String noteId;
  final String initialTitle;
  final String folder; // مجلد الملاحظة الجديدة فقط

  const EditorScreen({
    super.key,
    required this.noteId,
    this.initialTitle = 'ملاحظة جديدة',
    this.folder = '',
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _title;
  final List<_PageData> _pages = [_PageData()];
  int _page = 0;
  DrawingTool _tool = DrawingTool.pen;
  Color _color = Colors.black;
  double _width = 3.0;
  bool _stylusOnly = false;
  bool _loaded = false;
  bool _dirty = false;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialTitle);
    _load();
  }

  Future<void> _load() async {
    final content = await NotesStore.loadContent(widget.noteId);
    if (!mounted) return;
    setState(() {
      if (content != null) {
        _title.text = content.title;
        _pages.clear();
        for (var i = 0; i < content.pages.length; i++) {
          _pages.add(_PageData(
            strokes: content.pages[i],
            background: content.backgrounds[i],
          ));
        }
        if (_pages.isEmpty) _pages.add(_PageData());
      }
      _loaded = true;
    });
  }

  // ---------- الحفظ ----------

  void _markDirty() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1200), _flush);
  }

  Future<void> _flush() async {
    _saveTimer?.cancel();
    if (!_dirty || !_loaded) return;
    _dirty = false;
    await NotesStore.saveContent(
      id: widget.noteId,
      title: _title.text,
      pages: _pages.map((p) => p.strokes).toList(),
      backgrounds: _pages.map((p) => p.background).toList(),
      folder: widget.folder,
    );
  }

  Future<void> _manualSave() async {
    _dirty = true;
    await _flush();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم الحفظ على الجهاز')),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty && _loaded) _flush();
    _title.dispose();
    super.dispose();
  }

  // ---------- التحرير ----------

  void _commit(List<InkStroke> updated) {
    final page = _pages[_page];
    setState(() {
      page.undo.add(page.strokes);
      if (page.undo.length > 100) page.undo.removeAt(0);
      page.redo.clear();
      page.strokes = updated;
    });
    _markDirty();
  }

  void _undo() {
    final p = _pages[_page];
    if (p.undo.isEmpty) return;
    setState(() {
      p.redo.add(p.strokes);
      p.strokes = p.undo.removeLast();
    });
    _markDirty();
  }

  void _redo() {
    final p = _pages[_page];
    if (p.redo.isEmpty) return;
    setState(() {
      p.undo.add(p.strokes);
      p.strokes = p.redo.removeLast();
    });
    _markDirty();
  }

  void _setBackground(PageBackground bg) {
    setState(() => _pages[_page].background = bg);
    _markDirty();
  }

  void _addPage() {
    setState(() {
      // الصفحة الجديدة ترث خلفية الصفحة الحالية
      _pages.add(_PageData(background: _pages[_page].background));
      _page = _pages.length - 1;
    });
    _markDirty();
  }

  Future<void> _deletePage() async {
    final page = _pages[_page];
    if (page.strokes.isNotEmpty) {
      final ok = await confirmDialog(
        context,
        title: 'حذف الصفحة',
        message: _pages.length == 1
            ? 'سيتم مسح كل ما كُتب في هذه الصفحة. هل تريد المتابعة؟'
            : 'سيتم حذف الصفحة ${_page + 1} وكل ما فيها نهائيًا. هل تريد المتابعة؟',
        okLabel: 'حذف',
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      if (_pages.length == 1) {
        _pages[0] = _PageData(background: page.background);
      } else {
        _pages.removeAt(_page);
        _page = (_page - 1).clamp(0, _pages.length - 1);
      }
    });
    _markDirty();
  }

  String _bgLabel(PageBackground b) {
    switch (b) {
      case PageBackground.blank:
        return 'فارغ';
      case PageBackground.ruled:
        return 'مسطّر';
      case PageBackground.grid:
        return 'مربعات';
      case PageBackground.dots:
        return 'نقاط';
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final page = _pages[_page];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _flush();
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _title,
            onChanged: (_) => _markDirty(),
            decoration: const InputDecoration(
              hintText: 'عنوان الملاحظة',
              border: InputBorder.none,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'تراجع',
              onPressed: page.undo.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'إعادة',
              onPressed: page.redo.isEmpty ? null : _redo,
              icon: const Icon(Icons.redo),
            ),
            PopupMenuButton<PageBackground>(
              tooltip: 'خلفية الصفحة',
              icon: const Icon(Icons.grid_on),
              initialValue: page.background,
              onSelected: _setBackground,
              itemBuilder: (_) => PageBackground.values
                  .map((b) => PopupMenuItem<PageBackground>(
                        value: b,
                        child: Text(_bgLabel(b)),
                      ))
                  .toList(),
            ),
            IconButton(
              tooltip: 'حفظ',
              onPressed: _loaded ? _manualSave : null,
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _Toolbar(
                    tool: _tool,
                    color: _color,
                    width: _width,
                    stylusOnly: _stylusOnly,
                    onTool: (v) => setState(() => _tool = v),
                    onColor: (v) => setState(() => _color = v),
                    onWidth: (v) => setState(() => _width = v),
                    onStylusOnly: (v) => setState(() => _stylusOnly = v),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        if (wide)
                          SizedBox(
                            width: 110,
                            child: _PagesPanel(
                              axis: Axis.vertical,
                              count: _pages.length,
                              current: _page,
                              onSelect: (i) => setState(() => _page = i),
                              onAdd: _addPage,
                              onDelete: _deletePage,
                            ),
                          ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                    color: Color(0x22000000),
                                  ),
                                ],
                              ),
                              child: DrawingCanvas(
                                key: ValueKey(_page),
                                strokes: page.strokes,
                                background: page.background,
                                onChanged: _commit,
                                tool: _tool,
                                color: _color,
                                strokeWidth: _width,
                                stylusOnly: _stylusOnly,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!wide)
                    SizedBox(
                      height: 64,
                      child: _PagesPanel(
                        axis: Axis.horizontal,
                        count: _pages.length,
                        current: _page,
                        onSelect: (i) => setState(() => _page = i),
                        onAdd: _addPage,
                        onDelete: _deletePage,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final DrawingTool tool;
  final Color color;
  final double width;
  final bool stylusOnly;
  final ValueChanged<DrawingTool> onTool;
  final ValueChanged<Color> onColor;
  final ValueChanged<double> onWidth;
  final ValueChanged<bool> onStylusOnly;

  const _Toolbar({
    required this.tool,
    required this.color,
    required this.width,
    required this.stylusOnly,
    required this.onTool,
    required this.onColor,
    required this.onWidth,
    required this.onStylusOnly,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [
      Colors.black,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.amber,
    ];
    return Material(
      elevation: 1,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            _toolButton(Icons.edit, DrawingTool.pen, 'قلم'),
            _toolButton(Icons.highlight, DrawingTool.highlighter, 'هايلايتر'),
            _toolButton(Icons.auto_fix_high, DrawingTool.eraser, 'ممحاة'),
            const SizedBox(width: 8),
            ...colors.map((c) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () => onColor(c),
                    borderRadius: BorderRadius.circular(20),
                    child: CircleAvatar(
                      radius: color == c ? 15 : 12,
                      backgroundColor: c,
                      child: color == c
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),
                  ),
                )),
            const SizedBox(width: 8),
            SizedBox(
              width: 140,
              child: Row(
                children: [
                  const Icon(Icons.line_weight, size: 18),
                  Expanded(
                    child: Slider(
                      value: width,
                      min: 1,
                      max: 15,
                      onChanged: onWidth,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              avatar: const Icon(Icons.draw, size: 18),
              label: const Text('قلم فقط'),
              selected: stylusOnly,
              onSelected: onStylusOnly,
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(IconData icon, DrawingTool value, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ChoiceChip(
        selected: tool == value,
        label: Text(label),
        avatar: Icon(icon, size: 18),
        onSelected: (_) => onTool(value),
      ),
    );
  }
}

class _PagesPanel extends StatelessWidget {
  final Axis axis;
  final int count;
  final int current;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onDelete;

  const _PagesPanel({
    required this.axis,
    required this.count,
    required this.current,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: ListView.separated(
        scrollDirection: axis,
        padding: const EdgeInsets.all(8),
        itemCount: count + 2,
        separatorBuilder: (_, __) => const SizedBox(width: 8, height: 8),
        itemBuilder: (context, i) {
          if (i == count) {
            return IconButton(
              tooltip: 'صفحة جديدة',
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle_outline),
            );
          }
          if (i == count + 1) {
            return IconButton(
              tooltip: 'حذف الصفحة',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            );
          }
          return Center(
            child: InkWell(
              onTap: () => onSelect(i),
              child: Container(
                width: 54,
                height: axis == Axis.vertical ? 72 : 48,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    width: i == current ? 2 : 1,
                    color: i == current
                        ? scheme.primary
                        : Theme.of(context).dividerColor,
                  ),
                ),
                alignment: Alignment.center,
                child: Text('${i + 1}'),
              ),
            ),
          );
        },
      ),
    );
  }
}

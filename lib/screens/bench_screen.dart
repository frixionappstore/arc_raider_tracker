import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../data/bench_data.dart';
import '../data/item_library.dart';
import '../models/game_models.dart';

class BenchScreen extends StatefulWidget {
  final String userName;
  const BenchScreen({super.key, required this.userName});

  @override
  State<BenchScreen> createState() => _BenchScreenState();
}

class _BenchScreenState extends State<BenchScreen> {
  Map<String, int> _materialProgress = {};
  Map<String, int> _benchLevels = {};
  Timer? _timer;

  String get _progressKey => 'bench_progress_${widget.userName}';
  String get _levelKey => 'bench_levels_${widget.userName}';

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final progressData = prefs.getString(_progressKey);
    final levelData = prefs.getString(_levelKey);
    if (mounted) {
      setState(() {
        if (progressData != null) _materialProgress = Map<String, int>.from(json.decode(progressData));
        if (levelData != null) _benchLevels = Map<String, int>.from(json.decode(levelData));
      });
    }
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_progressKey, json.encode(_materialProgress));
    await prefs.setString(_levelKey, json.encode(_benchLevels));
  }

  void _changeMaterialCount(String itemId, int delta, int max, VoidCallback onComplete) {
    setState(() {
      int current = _materialProgress[itemId] ?? 0;
      _materialProgress[itemId] = (current + delta).clamp(0, max);
    });
    onComplete();
    _saveProgress();
  }

  void _startTimer(String itemId, int delta, int max, VoidCallback onComplete) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      int current = _materialProgress[itemId] ?? 0;
      if ((delta > 0 && current < max) || (delta < 0 && current > 0)) {
        _changeMaterialCount(itemId, delta, max, onComplete);
      } else {
        _timer?.cancel();
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  void _checkAndUpgradeLevel(Bench bench) {
    int currentLevel = _benchLevels[bench.name] ?? (bench.levels.first.level - 1);
    if (currentLevel >= bench.levels.last.level) return;

    BenchLevel? nextLevel;
    try {
      nextLevel = bench.levels.firstWhere((lvl) => lvl.level > currentLevel);
    } catch (e) {
      nextLevel = null;
    }

    if (nextLevel == null) return;

    bool canUpgrade = nextLevel.materials.every((mat) {
      return (_materialProgress[mat.itemId] ?? 0) >= mat.quantity;
    });

    if (canUpgrade) {
      setState(() {
        _benchLevels[bench.name] = nextLevel!.level;
      });
    }
  }

  void _shareBenchProgress() {
    final List<String> lines = ["ARC Raider Tracker - Atölye İhtiyaç Listem (${widget.userName}):\n"];
    bool anyNeed = false;

    for (var bench in BenchData.allBenches) {
      int currentLevel = _benchLevels[bench.name] ?? (bench.levels.first.level - 1);
      BenchLevel? activeLevel;
      try {
        activeLevel = bench.levels.firstWhere((lvl) => lvl.level > currentLevel);
      } catch (e) {
        activeLevel = null;
      }

      if (activeLevel != null) {
        List<String> neededMaterials = [];
        for (var mat in activeLevel.materials) {
          int current = _materialProgress[mat.itemId] ?? 0;
          if (current < mat.quantity) {
            final gameItem = ItemLibrary.resourceItems.firstWhere((item) => item.id == mat.itemId, orElse: () => GameItem(id: "", nameTr: mat.itemId, fileName: ""));
            neededMaterials.add("  - ${gameItem.nameTr}: $current/${mat.quantity}");
          }
        }

        if (neededMaterials.isNotEmpty) {
          anyNeed = true;
          lines.add("* ${bench.name} (Seviye ${activeLevel.level} için eksikler):");
          lines.addAll(neededMaterials);
          lines.add("");
        }
      }
    }

    if (!anyNeed) {
      lines.add("Tüm tezgahlar maksimum seviyede veya şu anki aşamalar için eksik malzeme yok! 🛡️");
    }

    Share.share(lines.join("\n"), subject: "Atölye İhtiyaç Listesi");
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("ATÖLYE"),
        backgroundColor: Colors.transparent,
        actions: [IconButton(icon: const Icon(Icons.share, color: Colors.orangeAccent), onPressed: _shareBenchProgress, tooltip: "İlerlemeyi Paylaş")],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(top: 10, bottom: 30),
        itemCount: BenchData.allBenches.length,
        itemBuilder: (context, index) => _buildBenchExpansionTile(BenchData.allBenches[index], isDark),
      ),
    );
  }

  Widget _buildBenchExpansionTile(Bench bench, bool isDark) {
    final String imagePath = 'assets/images/${bench.id}.png';
    int currentLevel = _benchLevels[bench.name] ?? (bench.levels.first.level - 1);
    
    // Spesifik tezgah için yüzde hesaplama
    int totalBenchLevels = bench.levels.length;
    int completedLevelsCount = 0;
    for (var lvl in bench.levels) {
      if (currentLevel >= lvl.level) completedLevelsCount++;
    }
    double progressPercent = (completedLevelsCount / totalBenchLevels) * 100;

    return Card(
      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: !isDark ? BorderSide(color: Colors.grey[200]!) : BorderSide.none),
      child: ExpansionTile(
        leading: Image.asset(imagePath, width: 40, height: 40, errorBuilder: (c, e, s) => Icon(Icons.build_circle_outlined, color: isDark ? Colors.grey : Colors.orangeAccent, size: 40)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(bench.name, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 18)),
            Text("%${progressPercent.toStringAsFixed(0)}", style: TextStyle(color: Colors.orangeAccent.withOpacity(0.8), fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        subtitle: Text("Seviye: $currentLevel", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: bench.levels.map((level) => _buildLevelInfo(bench, level, isDark)).toList(),
      ),
    );
  }

  Widget _buildLevelInfo(Bench bench, BenchLevel level, bool isDark) {
    int currentBenchLevel = _benchLevels[bench.name] ?? (bench.levels.first.level - 1);
    bool isLevelComplete = currentBenchLevel >= level.level;

    BenchLevel? nextLevel;
    try {
      nextLevel = bench.levels.firstWhere((lvl) => lvl.level > currentBenchLevel);
    } catch(e) {
      nextLevel = null;
    }
    bool isLevelActive = !isLevelComplete && (nextLevel?.level == level.level);

    Color levelColor = isDark ? Colors.grey : Colors.black45;
    if (isLevelComplete) levelColor = Colors.green;
    if (isLevelActive) levelColor = Colors.orangeAccent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 15.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isLevelComplete ? "Seviye ${level.level} (Tamamlandı)" : "Seviye ${level.level}",
            style: TextStyle(color: levelColor, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ...level.materials.map((mat) {
            GameItem? gameItem;
            try {
              gameItem = ItemLibrary.resourceItems.firstWhere((item) => item.id == mat.itemId);
            } catch (e) {
              gameItem = null;
            }
            return _buildMaterialRow(mat, gameItem, isLevelActive, isDark, () => _checkAndUpgradeLevel(bench));
          }),
        ],
      ),
    );
  }

  Widget _buildMaterialRow(RequiredMaterial material, GameItem? gameItem, bool isActive, bool isDark, VoidCallback onComplete) {
    int currentAmount = _materialProgress[material.itemId] ?? 0;
    int requiredAmount = material.quantity;
    bool isMaterialComplete = currentAmount >= requiredAmount;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(width: 35, height: 35, child: gameItem != null ? Image.asset("assets/items/${gameItem.fileName}", errorBuilder: (c, e, s) => const Icon(Icons.error, color: Colors.red)) : const Icon(Icons.help, color: Colors.grey)),
          const SizedBox(width: 15),
          Expanded(child: Text(gameItem?.nameTr ?? "Bilinmeyen Eşya", style: TextStyle(color: isActive ? (isDark ? Colors.white70 : Colors.black87) : (isDark ? Colors.grey : Colors.black38), fontSize: 14))),
          Row(
            children: [
              _buildCountButton(Icons.remove, isActive ? () => _changeMaterialCount(material.itemId, -1, requiredAmount, onComplete) : null, isActive, isDark, onLongPressStart: isActive ? (details) => _startTimer(material.itemId, -1, requiredAmount, onComplete) : null, onLongPressEnd: isActive ? (details) => _stopTimer() : null),
              SizedBox(
                width: 55,
                child: Center(child: Text("$currentAmount/$requiredAmount", style: TextStyle(color: isMaterialComplete ? (isDark ? Colors.greenAccent : Colors.green) : (isActive ? (isDark ? Colors.white : Colors.black87) : (isDark ? Colors.grey : Colors.black38)), fontSize: 14, fontWeight: FontWeight.w600))),
              ),
              _buildCountButton(Icons.add, isActive ? () => _changeMaterialCount(material.itemId, 1, requiredAmount, onComplete) : null, isActive, isDark, onLongPressStart: isActive ? (details) => _startTimer(material.itemId, 1, requiredAmount, onComplete) : null, onLongPressEnd: isActive ? (details) => _stopTimer() : null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCountButton(IconData icon, VoidCallback? onTap, bool isActive, bool isDark, {void Function(LongPressStartDetails)? onLongPressStart, void Function(LongPressEndDetails)? onLongPressEnd}) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: onLongPressStart,
      onLongPressEnd: onLongPressEnd,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isActive ? (isDark ? Colors.white.withOpacity(0.1) : Colors.orangeAccent.withOpacity(0.1)) : (isDark ? Colors.black.withOpacity(0.2) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(5)
        ),
        child: Icon(icon, color: isActive ? (isDark ? Colors.white : Colors.orangeAccent) : Colors.grey.withOpacity(0.5), size: 18),
      ),
    );
  }
}

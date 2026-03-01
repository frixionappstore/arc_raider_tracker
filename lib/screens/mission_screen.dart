import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../data/item_library.dart';
import '../data/mission_data.dart';
import '../models/game_models.dart';

class MissionScreen extends StatefulWidget {
  final String userName;
  const MissionScreen({super.key, required this.userName});

  @override
  State<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends State<MissionScreen> {
  Map<String, int> _missionProgress = {};
  Map<String, int> _missionStages = {};
  Timer? _timer;
  final int _coinStep = 10000;

  String get _progressKey => 'mission_progress_${widget.userName}';
  String get _stageKey => 'mission_stages_${widget.userName}';

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
    final stageData = prefs.getString(_stageKey);
    if (mounted) {
      setState(() {
        if (progressData != null) _missionProgress = Map<String, int>.from(json.decode(progressData));
        if (stageData != null) _missionStages = Map<String, int>.from(json.decode(stageData));
      });
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_progressKey, json.encode(_missionProgress));
    await prefs.setString(_stageKey, json.encode(_missionStages));
  }

  void _changeRequirementCount(MissionRequirement req, String key, int delta) {
    setState(() {
      int current = _missionProgress[key] ?? 0;
      int step = (req.type == RequirementType.coin) ? (delta.abs() == 10 ? 100000 : 10000) : 1;
      _missionProgress[key] = (current + (delta.sign * step)).clamp(0, req.requiredAmount);
    });
    _checkAndCompleteStage(req);
    _saveData();
  }

  void _startTimer(MissionRequirement req, String key, int delta) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _changeRequirementCount(req, key, delta);
      if ((_missionProgress[key] == 0 && delta < 0) || (_missionProgress[key] == req.requiredAmount && delta > 0)) {
        _timer?.cancel();
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  void _checkAndCompleteStage(MissionRequirement changedReq) {
    for (var mission in MissionData.allMissions) {
      for (var stage in mission.stages) {
        if (stage.requirements.any((r) => r.id == changedReq.id)) {
          int currentStageCount = _missionStages[mission.name] ?? 0;
          if (stage.stageNumber != currentStageCount + 1) continue;
          bool stageNowComplete = stage.requirements.every((req) {
            final key = "${mission.name}_${stage.name}_${req.id}";
            return (_missionProgress[key] ?? 0) >= req.requiredAmount;
          });
          if (stageNowComplete) {
            setState(() {
              _missionStages[mission.name] = stage.stageNumber;
            });
          }
          return;
        }
      }
    }
  }

  void _shareSingleMissionProgress(Mission mission) {
    final List<String> lines = ["ARC Raider Tracker - ${mission.name} İhtiyaç Listem (${widget.userName}):\n"];
    int completedStages = _missionStages[mission.name] ?? 0;
    
    MissionStage? activeStage;
    try {
      activeStage = mission.stages.firstWhere((s) => s.stageNumber == completedStages + 1);
    } catch (e) {
      activeStage = null;
    }

    if (activeStage != null) {
      List<String> neededReqs = [];
      for (var req in activeStage.requirements) {
        final key = "${mission.name}_${activeStage.name}_${req.id}";
        int current = _missionProgress[key] ?? 0;
        if (current < req.requiredAmount) {
          if (req.type == RequirementType.item) {
            final gameItem = ItemLibrary.resourceItems.firstWhere((item) => item.id == req.id, orElse: () => GameItem(id: "", nameTr: req.id, fileName: ""));
            neededReqs.add("  - ${gameItem.nameTr}: $current/${req.requiredAmount}");
          } else {
            String curStr = current.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
            String reqStr = req.requiredAmount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
            neededReqs.add("  - ${req.displayName ?? req.id}: $curStr/$reqStr");
          }
        }
      }

      if (neededReqs.isNotEmpty) {
        lines.add("* ${activeStage.stageNumber}. ${activeStage.name} için eksikler:");
        lines.addAll(neededReqs);
      } else {
        lines.add("Bu aşama için eksik kalmadı, bir sonrakine geçmeye hazırsın! 🛡️");
      }
    } else {
      lines.add("Tebrikler! ${mission.name} projesini tamamen bitirdin! 🏆");
    }

    Share.share(lines.join("\n"), subject: "${mission.name} İhtiyaç Listesi");
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("RAİDERS PROJELERİ"),
        backgroundColor: Colors.transparent,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: MissionData.allMissions.length,
        itemBuilder: (context, index) => _buildMissionCard(MissionData.allMissions[index], isDark),
      ),
    );
  }

  Widget _buildMissionCard(Mission mission, bool isDark) {
    if (mission.isLocked) return _buildLockedMissionCard(mission, isDark);
    int completedStages = _missionStages[mission.name] ?? 0;
    
    double progressPercent = mission.stages.isNotEmpty 
        ? (completedStages / mission.stages.length) * 100 
        : 0;

    return Card(
      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: !isDark ? BorderSide(color: Colors.grey[200]!) : BorderSide.none),
      child: ExpansionTile(
        leading: Image.asset(mission.imagePath, width: 60),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(mission.name, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 20))),
            Row(
              children: [
                Text("%${progressPercent.toStringAsFixed(0)}", style: TextStyle(color: Colors.greenAccent.withOpacity(0.8), fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.share, size: 20, color: Colors.greenAccent),
                  onPressed: () => _shareSingleMissionProgress(mission),
                  tooltip: "Bu Projeyi Paylaş",
                ),
              ],
            ),
          ],
        ),
        subtitle: Text("Tamamlanan Aşama: $completedStages / ${mission.stages.length}", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        children: mission.stages.map((stage) => _buildStageTile(mission, stage, isDark)).toList(),
      ),
    );
  }

  Widget _buildLockedMissionCard(Mission mission, bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF1A1A1A) : Colors.grey[100],
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: ListTile(
        leading: Image.asset(mission.imagePath, width: 60, opacity: const AlwaysStoppedAnimation(0.5)),
        title: Text(mission.name, style: TextStyle(color: isDark ? Colors.grey : Colors.black38, fontWeight: FontWeight.bold, fontSize: 20)),
        subtitle: const Text("Çok Yakında...", style: TextStyle(color: Colors.orangeAccent)),
        trailing: const Icon(Icons.lock, color: Colors.grey),
      ),
    );
  }

  Widget _buildStageTile(Mission mission, MissionStage stage, bool isDark) {
    int currentMissionStageCount = _missionStages[mission.name] ?? 0;
    bool isStageComplete = currentMissionStageCount >= stage.stageNumber;
    bool isStageActive = !isStageComplete && stage.stageNumber == currentMissionStageCount + 1;

    Color stageColor = isDark ? Colors.grey : Colors.black45;
    if (isStageComplete) stageColor = Colors.green;
    if (isStageActive) stageColor = Colors.orangeAccent;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: !isDark ? Border.all(color: Colors.grey[200]!) : null
      ),
      child: ExpansionTile(
        title: Text(
          isStageComplete ? "${stage.stageNumber}. ${stage.name} (Tamamlandı)" : "${stage.stageNumber}. ${stage.name}",
          style: TextStyle(color: stageColor, fontWeight: FontWeight.bold),
        ),
        childrenPadding: const EdgeInsets.all(10),
        children: stage.requirements.map((req) => _buildRequirementRow(mission, stage, req, isStageActive, isDark)).toList(),
      ),
    );
  }

  Widget _buildRequirementRow(Mission mission, MissionStage stage, MissionRequirement req, bool isActive, bool isDark) {
    final key = "${mission.name}_${stage.name}_${req.id}";
    int currentAmount = _missionProgress[key] ?? 0;
    bool isComplete = currentAmount >= req.requiredAmount;

    GameItem? gameItem;
    if (req.type == RequirementType.item) {
      try {
        gameItem = ItemLibrary.resourceItems.firstWhere((item) => item.id == req.id);
      } catch (e) {
        gameItem = null;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          SizedBox(width: 35, height: 35, child: req.type == RequirementType.item ? (gameItem != null ? Image.asset("assets/items/${gameItem.fileName}", errorBuilder: (c, e, s) => const Icon(Icons.error, color: Colors.red)) : const Icon(Icons.help, color: Colors.grey)) : const Icon(Icons.monetization_on, color: Colors.yellow, size: 30)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(gameItem?.nameTr ?? req.displayName ?? req.id, style: TextStyle(color: isActive ? (isDark ? Colors.white70 : Colors.black87) : (isDark ? Colors.grey : Colors.black38))),
              if (req.description != null) Text(req.description!, style: TextStyle(color: isActive ? Colors.grey : Colors.grey.withOpacity(0.5), fontSize: 10)),
            ]),
          ),
          Row(
            children: [
              _buildCountButton(Icons.remove, isActive ? () => _changeRequirementCount(req, key, -1) : null, isActive, isDark, onLongPressStart: isActive ? (details) => _startTimer(req, key, -1) : null, onLongPressEnd: isActive ? (details) => _stopTimer() : null),
              SizedBox(
                width: req.type == RequirementType.coin ? 110 : 60,
                child: Center(
                  child: Text(
                    req.type == RequirementType.coin ? "${currentAmount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}" : "$currentAmount/${req.requiredAmount}",
                    style: TextStyle(color: isComplete ? (isDark ? Colors.greenAccent : Colors.green) : (isActive ? (isDark ? Colors.white : Colors.black87) : (isDark ? Colors.grey : Colors.black38)), fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center,
                  ),
                ),
              ),
              _buildCountButton(Icons.add, isActive ? () => _changeRequirementCount(req, key, 1) : null, isActive, isDark, onLongPressStart: isActive ? (details) => _startTimer(req, key, 1) : null, onLongPressEnd: isActive ? (details) => _stopTimer() : null),
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
          color: isActive ? (isDark ? Colors.white.withOpacity(0.1) : Colors.green.withOpacity(0.1)) : (isDark ? Colors.black.withOpacity(0.2) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(5)
        ),
        child: Icon(icon, color: isActive ? (isDark ? Colors.white : Colors.green) : Colors.grey.withOpacity(0.5), size: 18),
      ),
    );
  }
}
